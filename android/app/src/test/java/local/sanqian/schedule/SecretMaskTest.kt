package local.sanqian.schedule

import org.junit.Assert.assertEquals
import org.junit.Test

class SecretMaskTest {
    @Test
    fun apiKeyKeepsAShortHeadAndTail() {
        assertEquals("sk-••••abcd", SecretMask.apiKey("sk-1234567890abcd"))
        assertEquals("fix••••-key", SecretMask.apiKey("  fixture-key  "))
    }

    @Test
    fun shortSecretsStayFullyHidden() {
        assertEquals(SecretMask.PLACEHOLDER, SecretMask.apiKey("short"))
        assertEquals(SecretMask.PLACEHOLDER, SecretMask.apiKey("12345678"))
    }
}
