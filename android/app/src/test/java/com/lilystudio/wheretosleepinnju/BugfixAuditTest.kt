package com.lilystudio.wheretosleepinnju

import org.junit.Assert.assertEquals
import java.lang.reflect.Proxy
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class BugfixAuditTest {
    private val hosts = setOf("iam.zgysyjy.org.cn")

    @Test
    fun httpNavigationUpgradesOnlyExactAllowedHosts() {
        val plain = SchoolPortalSecurity.decide("http://iam.zgysyjy.org.cn/am/UI/Login?ticket=1#frag", hosts)
        assertEquals(
            PortalNavigation.Upgrade("https://iam.zgysyjy.org.cn/am/UI/Login?ticket=1#frag"),
            plain
        )
        val explicit = SchoolPortalSecurity.decide("http://iam.zgysyjy.org.cn:443/path", hosts)
        assertEquals(PortalNavigation.Upgrade("https://iam.zgysyjy.org.cn:443/path"), explicit)
        val port80 = SchoolPortalSecurity.decide("http://iam.zgysyjy.org.cn:80/a?q=1#f", hosts)
        assertEquals(PortalNavigation.Upgrade("https://iam.zgysyjy.org.cn/a?q=1#f"), port80)
        assertEquals(PortalNavigation.Block, SchoolPortalSecurity.decide("http://evil.example/path?q=1#f", hosts))
        assertEquals(
            PortalNavigation.Block,
            SchoolPortalSecurity.decide("http://user:pass@iam.zgysyjy.org.cn/path?ticket=1#frag", hosts)
        )
        assertEquals(
            PortalNavigation.Allow,
            SchoolPortalSecurity.decide("https://iam.zgysyjy.org.cn/am/UI/Login?ticket=1#frag", hosts)
        )
        assertEquals(PortalNavigation.Block, SchoolPortalSecurity.decide("http://iam.zgysyjy.org.cn:8080/path", hosts))

        val encodedReturn = "http://iam.zgysyjy.org.cn/a%2Fb?service=https%3A%2F%2Fexample.com%2Fx%3Fa%3D1%26b%3D2#x%2Fy"
        val upgraded = SchoolPortalSecurity.decide(encodedReturn, hosts)
        assertEquals(
            PortalNavigation.Upgrade(
                "https://iam.zgysyjy.org.cn/a%2Fb?service=https%3A%2F%2Fexample.com%2Fx%3Fa%3D1%26b%3D2#x%2Fy"
            ),
            upgraded
        )
        val parsed = java.net.URI((upgraded as PortalNavigation.Upgrade).url)
        assertEquals("service=https%3A%2F%2Fexample.com%2Fx%3Fa%3D1%26b%3D2", parsed.rawQuery)
        assertEquals(listOf("service=https%3A%2F%2Fexample.com%2Fx%3Fa%3D1%26b%3D2"), parsed.rawQuery!!.split("&"))
        assertEquals("/a%2Fb", parsed.rawPath)
        assertEquals("x%2Fy", parsed.rawFragment)

        assertEquals(
            PortalNavigation.Upgrade("https://iam.zgysyjy.org.cn/a%25b?q=%25&x=%26#f%2F"),
            SchoolPortalSecurity.decide("http://iam.zgysyjy.org.cn/a%25b?q=%25&x=%26#f%2F", hosts)
        )
        assertEquals(
            PortalNavigation.Upgrade("https://iam.zgysyjy.org.cn/p?a=%3D"),
            SchoolPortalSecurity.decide("http://iam.zgysyjy.org.cn/p?a=%3D", hosts)
        )
        assertEquals(
            PortalNavigation.Upgrade("https://iam.zgysyjy.org.cn/a%2Fb?q=%26#x%2Fy"),
            SchoolPortalSecurity.decide("http://iam.zgysyjy.org.cn:80/a%2Fb?q=%26#x%2Fy", hosts)
        )
        assertEquals(
            PortalNavigation.Upgrade("https://iam.zgysyjy.org.cn:443/a%2Fb?q=%3D"),
            SchoolPortalSecurity.decide("http://iam.zgysyjy.org.cn:443/a%2Fb?q=%3D", hosts)
        )
        assertEquals(
            PortalNavigation.Allow,
            SchoolPortalSecurity.decide(
                "https://iam.zgysyjy.org.cn/a%2Fb?service=https%3A%2F%2Fexample.com%2Fx%3Fa%3D1%26b%3D2#x%2Fy",
                hosts
            )
        )
    }

    @Test
    fun cookieResetContinuesWhenCleanupFinishesEvenIfNoCookieWasRemoved() {
        val empty = mutableListOf<String>()
        PortalStorageReset.reset(
            deleteWebStorage = { empty += "storage" },
            removeAllCookies = { done ->
                empty += "cookies"
                done(false)
            },
            onReady = { empty += "ready" },
            onFailure = { empty += "fail" }
        )
        assertEquals(listOf("storage", "cookies", "ready"), empty)

        val removed = mutableListOf<String>()
        PortalStorageReset.reset(
            deleteWebStorage = { removed += "storage" },
            removeAllCookies = { done ->
                removed += "cookies"
                done(true)
            },
            onReady = { removed += "ready" },
            onFailure = { removed += "fail" }
        )
        assertEquals(listOf("storage", "cookies", "ready"), removed)

        val storageFailure = mutableListOf<String>()
        var cookiesCalled = false
        PortalStorageReset.reset(
            deleteWebStorage = { throw IllegalStateException("storage") },
            removeAllCookies = {
                cookiesCalled = true
            },
            onReady = { storageFailure += "ready" },
            onFailure = { storageFailure += it }
        )
        assertFalse(cookiesCalled)
        assertEquals(listOf("无法清除网页存储，门户未打开。请点底部「重试」。"), storageFailure)

        val cookieFailure = mutableListOf<String>()
        PortalStorageReset.reset(
            deleteWebStorage = { },
            removeAllCookies = { throw IllegalStateException("cookies") },
            onReady = { cookieFailure += "ready" },
            onFailure = { cookieFailure += it }
        )
        assertEquals(listOf("无法清除登录 Cookie，门户未打开。请点底部「重试」。"), cookieFailure)

        val waiting = mutableListOf<String>()
        PortalStorageReset.reset(
            deleteWebStorage = { waiting += "storage" },
            removeAllCookies = { waiting += "cookies" },
            onReady = { waiting += "ready" },
            onFailure = { waiting += "fail" }
        )
        assertEquals(listOf("storage", "cookies"), waiting)
    }

    @Test
    fun pendingResultsCompleteOnceWhenTheHostDetaches() {
        val bridge = PendingBridgeResults()
        val portal = FakeReply()
        val permission = FakeReply()
        val recognize = FakeReply()
        bridge.track("portal", portal)
        bridge.track("permission", permission)
        val recognition = bridge.track("recognize", recognize)
        assertEquals(3, bridge.cancelAll("cancelled", "界面已销毁"))
        assertEquals("cancelled", portal.code)
        assertEquals("cancelled", permission.code)
        assertEquals("cancelled", recognize.code)
        assertEquals(0, bridge.cancelAll("cancelled", "插件已卸载"))
        assertFalse(recognition.success("late"))
        assertEquals(1, portal.calls)
        assertNull(bridge.take("portal"))
    }

    @Test
    fun legacyAlarmQueueIsNotSchedulable() {
        val names = ScheduleReminderScheduler::class.java.methods.map { it.name }.toSet()
        assertTrue(names.contains("clear"))
        assertFalse(names.contains("replace"))
        assertFalse(ScheduleReminderScheduler.shouldNotify(null, setOf("alarm")))
        assertFalse(ScheduleReminderScheduler.shouldNotify("alarm", emptySet()))
        assertTrue(ScheduleReminderScheduler.shouldNotify("alarm", setOf("alarm")))
    }

    @Test
    fun predictiveBackProxyCanBeStoredWithoutCrashing() {
        var calls = 0
        val proxy = Proxy.newProxyInstance(
            BackLike::class.java.classLoader,
            arrayOf(BackLike::class.java),
        ) { instance, method, args ->
            predictiveBackResult(instance, method.name, args) { calls += 1 }
        }
        val registered = HashMap<Any, String>()
        registered[proxy] = "portal"
        assertEquals("portal", registered[proxy])
        assertEquals(System.identityHashCode(proxy), proxy.hashCode())
        (proxy as BackLike).onBackInvoked()
        assertEquals(1, calls)
    }

    @Test
    fun portalCleanupDoesNotOpenAfterDestroyOrANewerAttempt() {
        assertTrue(portalCleanupMayOpen(epoch = 1, currentEpoch = 1, finishing = false, destroyed = false))
        assertFalse(portalCleanupMayOpen(epoch = 1, currentEpoch = 1, finishing = true, destroyed = false))
        assertFalse(portalCleanupMayOpen(epoch = 1, currentEpoch = 1, finishing = false, destroyed = true))
        assertFalse(portalCleanupMayOpen(epoch = 1, currentEpoch = 2, finishing = false, destroyed = false))
    }

    private interface BackLike {
        fun onBackInvoked()
    }

    private class FakeReply : BridgeReply {
        var value: Any? = null
        var code: String? = null
        var calls = 0
        override fun success(value: Any?) {
            calls += 1
            this.value = value
        }

        override fun error(code: String, message: String?) {
            calls += 1
            this.code = code
        }
    }
}
