package com.qingzhangmao.app;

import android.content.ContentResolver;
import android.content.ContentValues;
import android.content.Context;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.provider.MediaStore;
import android.webkit.JavascriptInterface;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.text.SimpleDateFormat;
import java.util.Arrays;
import java.util.Date;
import java.util.Locale;

/**
 * 网页 ⇄ 原生 存储桥。
 *
 * 数据落在 App 私有目录（不是浏览器缓存）：
 *   files/data/records.json         主文件，每次改动即时写盘
 *   files/data/backups/*.json       每日快照，保留最近 30 份
 *
 * 卸载 App 才会清空，日常升级、清缓存都不影响已录入的记录。
 */
public class StoreBridge {

    private final Context ctx;

    StoreBridge(Context c) {
        this.ctx = c.getApplicationContext();
        try {
            base().mkdirs();
            backups().mkdirs();
        } catch (Exception ignored) {
        }
    }

    private File base() {
        return new File(ctx.getFilesDir(), "data");
    }

    private File target() {
        return new File(base(), "records.json");
    }

    private File backups() {
        return new File(base(), "backups");
    }

    @JavascriptInterface
    public String read() {
        File f = target();
        if (!f.exists()) return "";
        try (java.io.FileInputStream in = new java.io.FileInputStream(f)) {
            byte[] buf = new byte[(int) f.length()];
            int off = 0;
            while (off < buf.length) {
                int n = in.read(buf, off, buf.length - off);
                if (n <= 0) break;
                off += n;
            }
            return new String(buf, 0, off, StandardCharsets.UTF_8);
        } catch (Exception e) {
            return "";
        }
    }

    @JavascriptInterface
    public void write(String json) {
        if (json == null) return;
        synchronized (StoreBridge.class) {
            dailyBackup();
            File tmp = new File(base(), "records.json.tmp");
            try (FileOutputStream out = new FileOutputStream(tmp)) {
                out.write(json.getBytes(StandardCharsets.UTF_8));
                out.flush();
                out.getFD().sync();
            } catch (Exception e) {
                return;
            }
            // 原子替换，避免写到一半断电把原文件写坏
            if (!tmp.renameTo(target())) {
                tmp.delete();
            }
        }
    }

    @JavascriptInterface
    public String path() {
        return target().getAbsolutePath();
    }

    /** 每天第一笔改动前，把当时的文件快照存一份 */
    private void dailyBackup() {
        File f = target();
        if (!f.exists()) return;
        String day = new SimpleDateFormat("yyyy-MM-dd", Locale.US).format(new Date());
        File dest = new File(backups(), "records-" + day + ".json");
        if (dest.exists()) return;
        try (InputStream in = new java.io.FileInputStream(f);
             OutputStream out = new FileOutputStream(dest)) {
            byte[] buf = new byte[8192];
            int n;
            while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
        } catch (IOException ignored) {
        }
        prune(30);
    }

    private void prune(int keep) {
        File[] list = backups().listFiles();
        if (list == null || list.length <= keep) return;
        Arrays.sort(list, (a, b) -> b.getName().compareTo(a.getName()));
        for (int i = keep; i < list.length; i++) {
            //noinspection ResultOfMethodCallIgnored
            list[i].delete();
        }
    }

    /**
     * 导出 JSON。Android 11+ 直接落到「下载/清帐猫/」，无需权限；
     * 老系统退到 App 外部目录（文件管理器仍可访问）。
     */
    @JavascriptInterface
    public String saveExport(String name, String content) {
        String safe = (name == null || name.trim().isEmpty()) ? "清帐猫备份.json" : name.replaceAll("[/\\\\:*?\"<>|]", "_");
        byte[] data = (content == null ? "" : content).getBytes(StandardCharsets.UTF_8);
        String where = "";

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ContentResolver cr = ctx.getContentResolver();
            ContentValues v = new ContentValues();
            v.put(MediaStore.Downloads.DISPLAY_NAME, safe);
            v.put(MediaStore.Downloads.MIME_TYPE, "application/json");
            v.put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/清帐猫");
            v.put(MediaStore.Downloads.IS_PENDING, 1);
            Uri uri = null;
            try {
                uri = cr.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, v);
                if (uri != null) {
                    try (OutputStream out = cr.openOutputStream(uri)) {
                        if (out != null) out.write(data);
                    }
                    v.clear();
                    v.put(MediaStore.Downloads.IS_PENDING, 0);
                    cr.update(uri, v, null, null);
                    where = "下载/清帐猫/" + safe;
                }
            } catch (Exception e) {
                if (uri != null) cr.delete(uri, null, null);
            }
        }

        if (where.isEmpty()) {
            File dir = new File(ctx.getExternalFilesDir(null), "exports");
            //noinspection ResultOfMethodCallIgnored
            dir.mkdirs();
            File f = new File(dir, safe);
            try (FileOutputStream out = new FileOutputStream(f)) {
                out.write(data);
                where = f.getAbsolutePath();
            } catch (Exception e) {
                return "";
            }
        }

        return where;
    }
}
