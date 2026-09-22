package com.lilystudio.wheretosleepinnju

import android.content.Context
import java.io.File

object ScheduleWidgetStore {
    const val FILE_NAME = "personal-schedule.json"

    fun file(context: Context): File = File(context.applicationContext.filesDir, FILE_NAME)

    fun write(context: Context, args: Map<*, *>) {
        val json = widgetSnapshotJson(args)
        val directory = context.applicationContext.filesDir
        if (!directory.exists() && !directory.mkdirs()) {
            throw IllegalStateException("共享课表写入失败")
        }
        val target = File(directory, FILE_NAME)
        val temporary = File(directory, "$FILE_NAME.tmp")
        temporary.writeText(json)
        if (!temporary.renameTo(target)) {
            target.writeText(json)
            temporary.delete()
        }
        if (!target.isFile || target.length() <= 0L) {
            throw IllegalStateException("共享课表写入失败")
        }
    }

    fun readText(context: Context): String? {
        val target = file(context)
        if (!target.isFile) return null
        return target.readText()
    }
}
