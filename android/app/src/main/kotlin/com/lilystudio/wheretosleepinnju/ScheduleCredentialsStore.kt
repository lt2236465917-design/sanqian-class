package com.lilystudio.wheretosleepinnju

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import org.json.JSONObject
import java.nio.ByteBuffer
import java.security.KeyStore
import java.security.MessageDigest
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class ScheduleCredentialsStore private constructor(context: Context) {
    private val app = context.applicationContext
    private val prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private val lock = Any()

    data class SchoolAccountMetadata(val account: String, val accountLocalId: String)

    fun saveDeepSeekAPIKey(key: String) {
        val value = key.trim()
        if (value.isEmpty()) throw ScheduleCredentialsStoreError.InvalidValue
        save(value.toByteArray(Charsets.UTF_8), ITEM_API_KEY)
    }

    fun loadDeepSeekAPIKey(): String? {
        val data = load(ITEM_API_KEY) ?: return null
        val key = String(data, Charsets.UTF_8)
        if (key.isEmpty()) throw ScheduleCredentialsStoreError.InvalidValue
        return key
    }

    fun hasDeepSeekAPIKey(): Boolean = load(ITEM_API_KEY) != null

    fun deleteDeepSeekAPIKey() = delete(ITEM_API_KEY)

    fun saveSchoolCredentials(account: String, password: String): SchoolAccountMetadata {
        synchronized(lock) {
            val username = account.trim()
            if (username.isEmpty() || password.isEmpty()) throw ScheduleCredentialsStoreError.InvalidValue
            val digest = sha256Hex(username.toByteArray(Charsets.UTF_8))
            val identityItem = "$ITEM_SCHOOL_IDENTITY_PREFIX$digest"
            val saved = load(identityItem)?.let { String(it, Charsets.UTF_8) }
            val localId = if (saved != null && isUuid(saved)) {
                saved
            } else {
                UUID.randomUUID().toString().also { save(it.toByteArray(Charsets.UTF_8), identityItem) }
            }
            val payload = JSONObject()
                .put("account", username)
                .put("password", password)
                .put("accountLocalId", localId)
                .toString()
                .toByteArray(Charsets.UTF_8)
            save(payload, ITEM_SCHOOL)
            return SchoolAccountMetadata(username, localId)
        }
    }

    fun schoolAccountMetadata(): SchoolAccountMetadata? {
        val value = schoolCredentials() ?: return null
        return SchoolAccountMetadata(value.first, value.third)
    }

    fun deleteSchoolCredentials() = delete(ITEM_SCHOOL)

    fun saveLegacyJw(username: String, password: String) {
        val account = username.trim()
        if (account.isEmpty() || password.isEmpty()) throw ScheduleCredentialsStoreError.InvalidValue
        val payload = JSONObject()
            .put("username", account)
            .put("password", password)
            .toString()
            .toByteArray(Charsets.UTF_8)
        save(payload, ITEM_JW)
    }

    fun loadLegacyJw(): Pair<String, String>? {
        val data = load(ITEM_JW) ?: return null
        val json = try {
            JSONObject(String(data, Charsets.UTF_8))
        } catch (_: Exception) {
            throw ScheduleCredentialsStoreError.InvalidValue
        }
        val account = json.optString("username")
        val password = json.optString("password")
        if (account.isEmpty() || password.isEmpty()) throw ScheduleCredentialsStoreError.InvalidValue
        return account to password
    }

    fun deleteLegacyJw() = delete(ITEM_JW)

    fun <T> withSchoolCredentials(fill: (String, String) -> T): T {
        val value = schoolCredentials() ?: throw ScheduleCredentialsStoreError.NotFound
        return fill(value.first, value.second)
    }

    private fun schoolCredentials(): Triple<String, String, String>? {
        val data = load(ITEM_SCHOOL) ?: return null
        val json = try {
            JSONObject(String(data, Charsets.UTF_8))
        } catch (_: Exception) {
            throw ScheduleCredentialsStoreError.InvalidValue
        }
        val username = json.optString("account")
        val password = json.optString("password")
        val id = json.optString("accountLocalId")
        if (username.isEmpty() || password.isEmpty() || !isUuid(id)) {
            throw ScheduleCredentialsStoreError.InvalidValue
        }
        return Triple(username, password, id)
    }

    private fun save(data: ByteArray, item: String) {
        synchronized(lock) {
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.ENCRYPT_MODE, secretKey())
            val iv = cipher.iv
            val ciphertext = cipher.doFinal(data)
            val packed = ByteBuffer.allocate(4 + iv.size + ciphertext.size)
                .putInt(iv.size)
                .put(iv)
                .put(ciphertext)
                .array()
            prefs.edit().putString(item, android.util.Base64.encodeToString(packed, android.util.Base64.NO_WRAP)).apply()
        }
    }

    private fun load(item: String): ByteArray? {
        synchronized(lock) {
            val encoded = prefs.getString(item, null) ?: return null
            val packed = try {
                android.util.Base64.decode(encoded, android.util.Base64.NO_WRAP)
            } catch (_: Exception) {
                throw ScheduleCredentialsStoreError.InvalidValue
            }
            if (packed.size < 5) throw ScheduleCredentialsStoreError.InvalidValue
            val buffer = ByteBuffer.wrap(packed)
            val ivSize = buffer.int
            if (ivSize <= 0 || ivSize > 32 || buffer.remaining() < ivSize) throw ScheduleCredentialsStoreError.InvalidValue
            val iv = ByteArray(ivSize)
            buffer.get(iv)
            val ciphertext = ByteArray(buffer.remaining())
            buffer.get(ciphertext)
            return try {
                val cipher = Cipher.getInstance(TRANSFORMATION)
                cipher.init(Cipher.DECRYPT_MODE, secretKey(), GCMParameterSpec(128, iv))
                cipher.doFinal(ciphertext)
            } catch (_: Exception) {
                throw ScheduleCredentialsStoreError.Status("decrypt")
            }
        }
    }

    private fun delete(item: String) {
        synchronized(lock) { prefs.edit().remove(item).apply() }
    }

    private fun secretKey(): SecretKey {
        val store = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        val existing = store.getEntry(KEY_ALIAS, null) as? KeyStore.SecretKeyEntry
        if (existing != null) return existing.secretKey
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .setRandomizedEncryptionRequired(true)
                .build()
        )
        return generator.generateKey()
    }

    companion object {
        private const val ANDROID_KEYSTORE = "AndroidKeyStore"
        private const val KEY_ALIAS = "com.sanqian.schedule.credentials.aes"
        private const val PREFS = "sanqian_schedule_credentials"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val ITEM_API_KEY = "deepseek.apiKey"
        private const val ITEM_SCHOOL = "deepseek.apiKey.school.active"
        private const val ITEM_JW = "legacy.jw.credentials"
        private const val ITEM_SCHOOL_IDENTITY_PREFIX = "deepseek.apiKey.school.identity."

        @Volatile private var instance: ScheduleCredentialsStore? = null

        fun get(context: Context): ScheduleCredentialsStore {
            return instance ?: synchronized(this) {
                instance ?: ScheduleCredentialsStore(context.applicationContext).also { instance = it }
            }
        }

        private fun sha256Hex(data: ByteArray): String {
            val digest = MessageDigest.getInstance("SHA-256").digest(data)
            return digest.joinToString("") { "%02x".format(it) }
        }

        private fun isUuid(value: String): Boolean {
            return try {
                UUID.fromString(value)
                value.length == 36
            } catch (_: Exception) {
                false
            }
        }
    }
}

sealed class ScheduleCredentialsStoreError(message: String) : Exception(message) {
    object InvalidValue : ScheduleCredentialsStoreError("凭据为空或格式无效")
    object NotFound : ScheduleCredentialsStoreError("未保存学校账号")
    class Status(code: String) : ScheduleCredentialsStoreError("无法访问安全凭据存储（$code）")
}
