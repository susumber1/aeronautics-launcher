import com.google.gson.*;
import java.io.*;
import java.nio.file.*;
import java.util.*;

/** Configures only the portable Aeronautics client's own directory. */
public final class AeronauticsSetup {
    private static final Gson JSON = new GsonBuilder().setPrettyPrinting().create();
    private static JsonObject read(Path file) throws IOException {
        return Files.exists(file) ? JsonParser.parseString(Files.readString(file)).getAsJsonObject() : new JsonObject();
    }
    private static void write(Path file, JsonObject value) throws IOException {
        Files.createDirectories(file.getParent());
        Path tmp = file.resolveSibling(file.getFileName() + ".tmp");
        Files.writeString(tmp, JSON.toJson(value) + "\n");
        Files.move(tmp, file, StandardCopyOption.REPLACE_EXISTING);
    }
    private static void quickPlay(JsonObject value, String address) {
        value.addProperty("quickPlay", "MULTIPLAYER");
        value.addProperty("quickPlayMultiplayer", address);
    }
    private static void servers(Path folder, String address) throws IOException {
        Files.createDirectories(folder);
        // servers.dat uses uncompressed NBT, unlike world/level.dat.
        Path tmp = folder.resolve("servers.dat.tmp");
        try (DataOutputStream out = new DataOutputStream(Files.newOutputStream(tmp))) {
            out.writeByte(10); out.writeUTF("");
            out.writeByte(9); out.writeUTF("servers"); out.writeByte(10); out.writeInt(1);
            out.writeByte(8); out.writeUTF("name"); out.writeUTF("Aeronautics — сервер друзей");
            out.writeByte(8); out.writeUTF("ip"); out.writeUTF(address);
            out.writeByte(1); out.writeUTF("acceptTextures"); out.writeByte(1);
            out.writeByte(0); out.writeByte(0);
        }
        Files.move(tmp, folder.resolve("servers.dat"), StandardCopyOption.REPLACE_EXISTING);
    }
    public static void main(String[] args) throws Exception {
        Path root = Path.of(args[0]).toAbsolutePath().normalize();
        String address = Files.readString(root.resolve("server-address.txt")).trim();
        if (!address.matches("[A-Za-z0-9.-]+:[0-9]{1,5}"))
            throw new IOException("Invalid address in server-address.txt; expected hostname:port");
        int port = Integer.parseInt(address.substring(address.lastIndexOf(':') + 1));
        if (port < 1 || port > 65535) throw new IOException("Invalid server port");
        Path config = root.resolve(".hmcl/config");
        Path game = root.resolve(".minecraft");
        JsonObject settings = read(config.resolve("game-settings.json"));
        settings.addProperty("$schema", "https://schemas.glavo.site/hmcl/game-settings/1.0.0");
        JsonArray presets = settings.has("presets") ? settings.getAsJsonArray("presets") : new JsonArray();
        if (presets.isEmpty()) {
            JsonObject preset = new JsonObject();
            preset.addProperty("id", "game-settings-preset:003c0673-7f1c-40b4-a8c0-2fc227f18436");
            preset.addProperty("autoNameNumber", 1);
            preset.addProperty("maxMemory", 5120);
            preset.addProperty("javaType", "VERSION");
            preset.addProperty("customJavaVersion", "21");
            presets.add(preset);
        }
        for (JsonElement preset : presets) quickPlay(preset.getAsJsonObject(), address);
        settings.add("presets", presets);
        write(config.resolve("game-settings.json"), settings);
        String presetId = presets.get(0).getAsJsonObject().get("id").getAsString();

        JsonObject directories = read(config.resolve("game-directories.json"));
        directories.addProperty("$schema", "https://schemas.glavo.site/hmcl/game-directories/1.0.0");
        JsonArray dirs = directories.has("directories") ? directories.getAsJsonArray("directories") : new JsonArray();
        JsonObject directory = dirs.isEmpty() ? new JsonObject() : dirs.get(0).getAsJsonObject();
        if (!directory.has("id")) directory.addProperty("id", "game-directory:685d3c1d-a097-49f9-b725-81fc8b149101");
        directory.addProperty("path", game.toString());
        directory.addProperty("legacyGameSettings", presetId);
        JsonArray onlyDirectory = new JsonArray(); onlyDirectory.add(directory);
        directories.add("directories", onlyDirectory);
        write(config.resolve("game-directories.json"), directories);

        JsonObject launcher = read(config.resolve("launcher-settings.json"));
        launcher.addProperty("$schema", "https://schemas.glavo.site/hmcl/launcher-settings/1.0.0");
        launcher.addProperty("language", "ru");
        launcher.addProperty("defaultGameSettingsPreset", presetId);
        launcher.addProperty("selectedGameDirectory", directory.get("id").getAsString());
        write(config.resolve("launcher-settings.json"), launcher);
        servers(game, address);
        Path versions = game.resolve("versions");
        if (Files.isDirectory(versions)) {
            try (var folders = Files.list(versions)) {
                for (Path version : folders.filter(Files::isDirectory).toList()) {
                    Path definition = version.resolve(version.getFileName() + ".json");
                    if (!Files.exists(definition)) continue;
                    String content = Files.readString(definition);
                    if (!version.getFileName().toString().toLowerCase(Locale.ROOT).contains("aeronautics") && !content.contains("neoForgeVersion")) continue;
                    Path file = version.resolve(".hmcl/config/instance-game-settings.json");
                    JsonObject instance = read(file);
                    instance.addProperty("$schema", "https://schemas.glavo.site/hmcl/instance-game-settings/1.0.0");
                    quickPlay(instance, address);
                    write(file, instance);
                    servers(version, address);
                }
            }
        }
        System.out.println("Aeronautics: automatic connection to " + address);
    }
}
