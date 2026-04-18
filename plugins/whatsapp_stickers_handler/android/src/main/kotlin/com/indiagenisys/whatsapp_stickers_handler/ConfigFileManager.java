package com.indiagenisys.whatsapp_stickers_handler;

import android.content.Context;
import android.util.Log;

import androidx.annotation.NonNull;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileReader;
import java.io.FileWriter;
import java.io.IOException;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Map;

import io.flutter.plugin.common.MethodCall;
import io.flutter.util.PathUtils;

public class ConfigFileManager {

    public static final String CONTENT_FILE_NAME = "sticker_packs.json";

    static List<StickerPack> getStickerPacks(Context context) {
        List<StickerPack> stickerPackList;
        File file = new File(getConfigFilePath(context));
        if (!file.exists()) {
            return new ArrayList<StickerPack>();
        }
        try (InputStream contentsInputStream = new FileInputStream(file)) {
            stickerPackList = ContentFileParser.parseStickerPacks(contentsInputStream);
        } catch (IOException | IllegalStateException e) {
            throw new RuntimeException("config file has some issues: " + e.getMessage(), e);
        }
        return stickerPackList;
    }



    static StickerPack fromMethodCall(Context context, MethodCall call) {
        String identifier = call.argument("identifier");
        String name = call.argument("name");
        String publisher = call.argument("publisher");
        String trayImageFileName = call.argument("trayImageFileName");
        trayImageFileName = getFileName(trayImageFileName);
        String publisherWebsite = call.argument("publisherWebsite");
        String privacyPolicyWebsite = call.argument("privacyPolicyWebsite");
        String licenseAgreementWebsite = call.argument("licenseAgreementWebsite");
        boolean animatedStickerPack = call.argument("animatedStickerPack");
        Map<String, List<String>> stickers = call.argument("stickers");
        String imageDataVersion = call.argument("imageDataVersion");


        StickerPack newStickerPack = new StickerPack(
            identifier, name, publisher, trayImageFileName, "", 
            publisherWebsite, privacyPolicyWebsite, licenseAgreementWebsite, 
            imageDataVersion, false, animatedStickerPack);

        List<Sticker> newStickers = new ArrayList<Sticker>();
        assert stickers != null;
        for (Map.Entry<String, List<String>> entry : stickers.entrySet()) {
            Sticker s = new Sticker(getFileName(entry.getKey()), entry.getValue());
            newStickers.add(s);
        }
        newStickerPack.setStickers(newStickers);
        newStickerPack.setAndroidPlayStoreLink("");
        newStickerPack.setIosAppStoreLink("");
        return newStickerPack;
    }
    static String getWhatsappType(MethodCall call) {
        String whatsappType = call.argument("whatsappType");
        return whatsappType;
    }

    static boolean addNewPack(Context context, StickerPack stickerPack) throws JSONException, InvalidPackException {
        List<StickerPack> stickerPacks = new ArrayList<>();

        for (StickerPack existingPack : getStickerPacks(context)) {
            if (!existingPack.identifier.equals(stickerPack.identifier)) {
                // Keep unrelated packs
                stickerPacks.add(existingPack);
            } else {
                // If it's the same pack, clean up stickers no longer present
                for (Sticker existingSticker : existingPack.getStickers()) {
                    if (!stickerPack.getStickers().contains(existingSticker)) {
                        String fname = existingSticker.imageFileName.replace("._.", File.separator);
                        try {
                            new File(fname).delete();
                        } catch (Exception e) {
                            e.printStackTrace();
                        }
                    }
                }
                // Don't add existingPack here — it will be replaced by the new one
            }
        }

        // Do NOT override imageDataVersion here — it was passed correctly from Flutter
        Log.d("StickerDebug", "🧩 Writing pack: " + stickerPack.identifier + " | version: " + stickerPack.imageDataVersion);

        // Add (or replace) the updated pack
        stickerPacks.add(stickerPack);

        return updateConfigFile(context, stickerPacks);
    }


    static String getFileName(String name) {
        if (name.contains("assets://")) {
            name = name.replace("assets://", "");
            name = name.replace("/", "_SSP_");
        } else if (name.contains("file://")) {
            name = name.replace("file://", "");
            name = name.replace("/", "._.");
        }
        return name;
    }

    static boolean updateConfigFile(Context context, List<StickerPack> stickerPacks) throws JSONException, InvalidPackException {
        JSONObject mObj = new JSONObject();
        if (stickerPacks.size() <= 0) {
            mObj.put("android_play_store_link", "");
            mObj.put("ios_app_store_link", "");
        } else {
            mObj.put("android_play_store_link", stickerPacks.get(0).androidPlayStoreLink);
            mObj.put("ios_app_store_link", stickerPacks.get(0).iosAppStoreLink);
        }
        JSONArray _packs = new JSONArray();
        for (StickerPack s : stickerPacks) {
            JSONObject obj = new JSONObject();
            obj.put("identifier", s.identifier);
            obj.put("name", s.name);
            obj.put("publisher", s.publisher);
            obj.put("tray_image_file", getFileName(s.trayImageFile));
            obj.put("image_data_version", s.imageDataVersion);
            obj.put("avoid_cache", s.avoidCache);
            obj.put("animated_sticker_pack", s.animatedStickerPack);
            obj.put("publisher_email", s.publisherEmail);
            obj.put("publisher_website", s.publisherWebsite);
            obj.put("privacy_policy_website", s.privacyPolicyWebsite);
            obj.put("license_agreement_website", s.licenseAgreementWebsite);

            JSONArray stickerList = new JSONArray();
            for (Sticker _sticker : s.getStickers()) {
                JSONObject stickerObj = new JSONObject();
                String stickerFileName = getFileName(_sticker.imageFileName);
                stickerObj.put("image_file", stickerFileName);
                JSONArray _emojies = new JSONArray();
                for (String emoji : _sticker.emojis) {
                    _emojies.put(emoji);
                }
                stickerObj.put("emojis", _emojies);
                stickerList.put(stickerObj);
            }
            obj.put("stickers", stickerList);
            _packs.put(obj);
        }
        mObj.put("sticker_packs", _packs);
        writeConfigFile(context, mObj.toString());
        return true;
    }

    static void writeConfigFile(Context context, String jsonString) {
        String filePath = getConfigFilePath(context);
        File f = new File(filePath);
        try {
            FileWriter writer = new FileWriter(f);
            writer.write(jsonString);
//            Log.d("WaStickerLog", "StickerData WriteToConfig : " + jsonString);
            writer.close();
        } catch (IOException e) {
            e.printStackTrace();
        }
    }

    static void generateConfigFile(Context context) throws JSONException {
        File file = new File(getConfigFilePath(context));
        if (!file.exists()) {
            //prepare data
            JSONObject mObj = new JSONObject();
            mObj.put("android_play_store_link", "");
            mObj.put("ios_app_store_link", "");
            JSONArray _packs = new JSONArray();
            mObj.put("sticker_packs", _packs);
            // write in file
            writeConfigFile(context, mObj.toString());
        }
    }

    public static String readConfigFile(Context context) {
        File file = new File(getConfigFilePath(context));
        StringBuilder text = new StringBuilder();
        try {
            BufferedReader br = new BufferedReader(new FileReader(file));
            String line;
            while ((line = br.readLine()) != null) {
                text.append(line);
                text.append('\n');
            }
            br.close();
        } catch (IOException e) {
            e.printStackTrace();
        }
        return text.toString();
    }

    public static String getConfigFilePath(Context context) {
        return PathUtils.getDataDirectory(context) + File.separator + CONTENT_FILE_NAME;
    }

    /**
     * After Flutter migrates on-disk user pack images to .webp, update sticker_packs.json
     * so {@link ContentFileParser} can load (it rejects non-.webp sticker filenames).
     */
    static void migrateUserPackRefsToWebp(Context context) throws JSONException {
        File file = new File(getConfigFilePath(context));
        if (!file.exists()) {
            return;
        }
        String raw = readConfigFile(context);
        if (raw == null || raw.trim().isEmpty()) {
            return;
        }
        JSONObject root = new JSONObject(raw);
        if (!root.has("sticker_packs")) {
            return;
        }
        JSONArray packs = root.getJSONArray("sticker_packs");
        boolean changed = false;
        for (int i = 0; i < packs.length(); i++) {
            JSONObject pack = packs.getJSONObject(i);
            String id = pack.optString("identifier", "");
            if (!id.startsWith("user_local_")) {
                continue;
            }
            if (pack.has("tray_image_file")) {
                String tray = pack.getString("tray_image_file");
                String nw = replaceImageExtWithWebp(tray);
                if (!tray.equals(nw)) {
                    pack.put("tray_image_file", nw);
                    changed = true;
                }
            }
            if (!pack.has("stickers")) {
                continue;
            }
            JSONArray stickers = pack.getJSONArray("stickers");
            for (int j = 0; j < stickers.length(); j++) {
                JSONObject st = stickers.getJSONObject(j);
                String img = st.getString("image_file");
                String nw = replaceImageExtWithWebp(img);
                if (!img.equals(nw)) {
                    st.put("image_file", nw);
                    changed = true;
                }
            }
        }
        if (changed) {
            writeConfigFile(context, root.toString());
        }
    }

    private static String replaceImageExtWithWebp(String flattenedPath) {
        if (flattenedPath == null || flattenedPath.isEmpty()) {
            return flattenedPath;
        }
        String lower = flattenedPath.toLowerCase(Locale.US);
        if (lower.endsWith(".webp")) {
            return flattenedPath;
        }
        if (lower.endsWith(".png") || lower.endsWith(".jpg") || lower.endsWith(".jpeg")) {
            int lastDot = flattenedPath.lastIndexOf('.');
            if (lastDot >= 0) {
                return flattenedPath.substring(0, lastDot) + ".webp";
            }
        }
        return flattenedPath;
    }
}
