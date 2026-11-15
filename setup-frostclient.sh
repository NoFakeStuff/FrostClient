#!/bin/bash
# FrostClient one-file installer: run "bash setup-frostclient.sh" to create the full Fabric 1.21.11 project in ./frostclient
set -e
mkdir -p frostclient && cd frostclient
mkdir -p "."
cat > ".gitignore" <<'FROST_EOF_END'
.gradle/
build/
.idea/
run/
*.iml
FROST_EOF_END
mkdir -p "."
cat > "README.md" <<'FROST_EOF_END'
# FrostClient
Clean Fabric client mod for Minecraft 1.21.11. Press **Right Shift** to open the menu.
Features: Username + logo HUD, offline account switcher, Armor HUD, coordinates, FPS, ping, CPS, speed, memory, clock, potion HUD, keystrokes, toggle sprint, fullbright, zoom (C), custom crosshair.
Build: `gradle build` (Java 21) -> `build/libs/`.
FROST_EOF_END
mkdir -p "."
cat > "build.gradle" <<'FROST_EOF_END'
plugins {
    id 'fabric-loom' version '1.14-SNAPSHOT'
}
version = project.mod_version
group = 'net.frostclient'
base { archivesName = 'frostclient' }
repositories {}
dependencies {
    minecraft "com.mojang:minecraft:${project.minecraft_version}"
    mappings "net.fabricmc:yarn:${project.yarn_mappings}:v2"
    modImplementation "net.fabricmc:fabric-loader:${project.loader_version}"
    modImplementation "net.fabricmc.fabric-api:fabric-api:${project.fabric_version}"
}
tasks.withType(JavaCompile).configureEach { options.release = 21 }
java { sourceCompatibility = JavaVersion.VERSION_21; targetCompatibility = JavaVersion.VERSION_21 }
processResources {
    inputs.property "version", project.version
    filesMatching("fabric.mod.json") { expand "version": project.version }
}
FROST_EOF_END
mkdir -p "."
cat > "gradle.properties" <<'FROST_EOF_END'
org.gradle.jvmargs=-Xmx2G
minecraft_version=1.21.11
yarn_mappings=1.21.11+build.3
loader_version=0.18.2
fabric_version=0.141.0+1.21.11
mod_version=1.0.0
FROST_EOF_END
mkdir -p "."
cat > "settings.gradle" <<'FROST_EOF_END'
pluginManagement {
    repositories {
        maven { url = 'https://maven.fabricmc.net/' }
        mavenCentral()
        gradlePluginPortal()
    }
}
FROST_EOF_END
mkdir -p "src/main/java/net/frostclient"
cat > "src/main/java/net/frostclient/AccountManager.java" <<'FROST_EOF_END'
package net.frostclient;

import net.frostclient.mixin.MinecraftClientAccessor;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.session.Session;

import java.lang.reflect.Constructor;
import java.nio.charset.StandardCharsets;
import java.util.Optional;
import java.util.UUID;

/**
 * Offline account switcher. Changes the username/UUID of the local session.
 * Works in singleplayer and on offline-mode (cracked) servers only.
 * Premium servers will reject it. "Restore original" brings back your real login.
 */
public class AccountManager {
    private static Session original = null;

    public static String current() {
        return MinecraftClient.getInstance().getSession().getUsername();
    }

    public static boolean isValidName(String n) {
        return n != null && n.matches("[A-Za-z0-9_]{3,16}");
    }

    public static String switchTo(String name) {
        if (!isValidName(name)) return "Invalid name (3-16 letters, numbers, _)";
        try {
            MinecraftClient mc = MinecraftClient.getInstance();
            if (original == null) original = mc.getSession();
            UUID uuid = UUID.nameUUIDFromBytes(("OfflinePlayer:" + name).getBytes(StandardCharsets.UTF_8));
            ((MinecraftClientAccessor) mc).frost$setSession(build(name, uuid));
            return "Switched to " + name;
        } catch (Throwable t) {
            return "Switch failed: " + t.getClass().getSimpleName();
        }
    }

    public static String restore() {
        if (original == null) return "Already on your original account";
        ((MinecraftClientAccessor) MinecraftClient.getInstance()).frost$setSession(original);
        original = null;
        return "Restored original account";
    }

    // Session's constructor changes between versions, so fill it by parameter type.
    private static Session build(String name, UUID uuid) throws Exception {
        Constructor<?> ctor = Session.class.getConstructors()[0];
        Class<?>[] types = ctor.getParameterTypes();
        Object[] args = new Object[types.length];
        int strings = 0;
        for (int i = 0; i < types.length; i++) {
            Class<?> t = types[i];
            if (t == String.class) args[i] = (strings++ == 0) ? name : "0";
            else if (t == UUID.class) args[i] = uuid;
            else if (t == Optional.class) args[i] = Optional.empty();
            else if (t.isEnum()) args[i] = t.getEnumConstants()[0];
        }
        return (Session) ctor.newInstance(args);
    }
}
FROST_EOF_END
mkdir -p "src/main/java/net/frostclient"
cat > "src/main/java/net/frostclient/AccountScreen.java" <<'FROST_EOF_END'
package net.frostclient;

import net.minecraft.client.gui.DrawContext;
import net.minecraft.client.gui.screen.Screen;
import net.minecraft.client.gui.widget.ButtonWidget;
import net.minecraft.client.gui.widget.TextFieldWidget;
import net.minecraft.text.Text;

import java.util.List;

public class AccountScreen extends Screen {
    private static final int PH = 240, MAX_ACCOUNTS = 6;
    private final Screen parent;
    private TextFieldWidget field;
    private String status = "";

    public AccountScreen(Screen parent) {
        super(Text.literal("Accounts"));
        this.parent = parent;
    }

    private int y0() { return height / 2 - PH / 2; }

    @Override
    protected void init() {
        List<String> accounts = FrostConfig.get().accounts;
        int x = width / 2 - 100, y = y0();

        field = new TextFieldWidget(textRenderer, x, y + 50, 140, 20, Text.literal("Username"));
        field.setMaxLength(16);
        field.setPlaceholder(Text.literal("New username"));
        addDrawableChild(field);
        addDrawableChild(ButtonWidget.builder(Text.literal("Add"), b -> {
            String n = field.getText().trim();
            if (!AccountManager.isValidName(n)) status = "§cInvalid name (3-16 letters, numbers, _)";
            else if (accounts.contains(n)) status = "§cAlready saved";
            else if (accounts.size() >= MAX_ACCOUNTS) status = "§cMax " + MAX_ACCOUNTS + " accounts";
            else { accounts.add(n); FrostConfig.save(); status = "§bSaved " + n; clearAndInit(); }
        }).dimensions(x + 144, y + 50, 56, 20).build());

        int ry = y + 76;
        for (String name : List.copyOf(accounts)) {
            addDrawableChild(ButtonWidget.builder(Text.literal((name.equals(AccountManager.current()) ? "§b✔ " : "") + name), b -> {
                status = "§b" + AccountManager.switchTo(name);
                clearAndInit();
            }).dimensions(x, ry, 172, 20).build());
            addDrawableChild(ButtonWidget.builder(Text.literal("§cX"), b -> {
                accounts.remove(name);
                FrostConfig.save();
                clearAndInit();
            }).dimensions(x + 176, ry, 24, 20).build());
            ry += 22;
        }

        addDrawableChild(ButtonWidget.builder(Text.literal("Restore original"), b -> {
            status = "§b" + AccountManager.restore();
            clearAndInit();
        }).dimensions(x, y + PH - 52, 98, 20).build());
        addDrawableChild(ButtonWidget.builder(Text.literal("Back"), b -> close())
                .dimensions(x + 102, y + PH - 52, 98, 20).build());
    }

    @Override
    public void renderBackground(DrawContext ctx, int mouseX, int mouseY, float delta) {
        super.renderBackground(ctx, mouseX, mouseY, delta);
        int pw = 232, x = width / 2 - pw / 2, y = y0();
        ctx.fill(x, y, x + pw, y + PH, 0xD0101820);
        ctx.fill(x, y, x + pw, y + 2, FrostHud.ACCENT);
        FrostHud.drawLogo(ctx, x + 8, y + 8, 16);
        ctx.drawText(textRenderer, Text.literal("§b§lAccounts"), x + 28, y + 12, 0xFFFFFFFF, true);
        ctx.drawText(textRenderer, Text.literal("Current: §b" + AccountManager.current()), x + 16, y + 32, 0xFFFFFFFF, true);
        ctx.drawText(textRenderer, Text.literal(status), x + 16, y + PH - 22, 0xFFFFFFFF, true);
    }

    @Override
    public void close() { client.setScreen(parent); }
}
FROST_EOF_END
mkdir -p "src/main/java/net/frostclient"
cat > "src/main/java/net/frostclient/FrostClient.java" <<'FROST_EOF_END'
package net.frostclient;

import net.fabricmc.api.ClientModInitializer;
import net.fabricmc.fabric.api.client.event.lifecycle.v1.ClientTickEvents;
import net.fabricmc.fabric.api.client.keybinding.v1.KeyBindingHelper;
import net.fabricmc.fabric.api.client.rendering.v1.HudRenderCallback;
import net.fabricmc.fabric.api.client.screen.v1.ScreenEvents;
import net.fabricmc.fabric.api.client.screen.v1.Screens;
import net.minecraft.client.gui.screen.TitleScreen;
import net.minecraft.client.gui.widget.ButtonWidget;
import net.minecraft.text.Text;
import net.frostclient.mixin.SimpleOptionAccessor;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.option.KeyBinding;
import net.minecraft.client.option.SimpleOption;
import net.minecraft.client.util.InputUtil;
import net.minecraft.util.Identifier;
import org.lwjgl.glfw.GLFW;

public class FrostClient implements ClientModInitializer {
    public static KeyBinding openMenu;
    public static KeyBinding zoomKey;
    private static Double savedGamma = null;

    @Override
    public void onInitializeClient() {
        FrostConfig.load();

        KeyBinding.Category cat = KeyBinding.Category.create(Identifier.of("frostclient", "main"));
        openMenu = KeyBindingHelper.registerKeyBinding(new KeyBinding(
                "key.frostclient.menu", InputUtil.Type.KEYSYM, GLFW.GLFW_KEY_RIGHT_SHIFT, cat));
        zoomKey = KeyBindingHelper.registerKeyBinding(new KeyBinding(
                "key.frostclient.zoom", InputUtil.Type.KEYSYM, GLFW.GLFW_KEY_C, cat));

        ClientTickEvents.END_CLIENT_TICK.register(client -> {
            while (openMenu.wasPressed()) {
                if (client.currentScreen == null) client.setScreen(new FrostMenuScreen());
            }
            tickSprint(client);
            tickFullbright(client);
        });

        // quick account switcher button on the title screen
        ScreenEvents.AFTER_INIT.register((client, screen, w, h) -> {
            if (screen instanceof TitleScreen) {
                Screens.getButtons(screen).add(ButtonWidget.builder(Text.literal("§b❄ Accounts"),
                        b -> client.setScreen(new AccountScreen(screen))).dimensions(6, 6, 90, 20).build());
            }
        });

        HudRenderCallback.EVENT.register((ctx, tick) -> FrostHud.render(ctx));
    }

    public static boolean zooming() {
        return FrostConfig.get().zoom && zoomKey != null && zoomKey.isPressed();
    }

    private static void tickSprint(MinecraftClient mc) {
        if (!FrostConfig.get().toggleSprint || mc.player == null || mc.currentScreen != null) return;
        if (mc.options.forwardKey.isPressed() && !mc.player.isSneaking()) {
            mc.options.sprintKey.setPressed(true);
        }
    }

    @SuppressWarnings("unchecked")
    private static void tickFullbright(MinecraftClient mc) {
        SimpleOption<Double> gamma = mc.options.getGamma();
        boolean on = FrostConfig.get().fullbright;
        if (on) {
            if (savedGamma == null) savedGamma = gamma.getValue();
            if (gamma.getValue() != 16.0) ((SimpleOptionAccessor<Double>) (Object) gamma).frost$setValue(16.0);
        } else if (savedGamma != null) {
            ((SimpleOptionAccessor<Double>) (Object) gamma).frost$setValue(savedGamma);
            savedGamma = null;
        }
    }
}
FROST_EOF_END
mkdir -p "src/main/java/net/frostclient"
cat > "src/main/java/net/frostclient/FrostConfig.java" <<'FROST_EOF_END'
package net.frostclient;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import net.fabricmc.loader.api.FabricLoader;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;

public class FrostConfig {
    private static final Gson GSON = new GsonBuilder().setPrettyPrinting().create();
    private static final Path FILE = FabricLoader.getInstance().getConfigDir().resolve("frostclient.json");
    private static FrostConfig instance = new FrostConfig();

    // Accounts
    public List<String> accounts = new ArrayList<>();
    // HUD
    public boolean username = true;
    public boolean armorHud = true;
    public boolean coordinates = true;
    public boolean fps = true;
    public boolean ping = true;
    public boolean cps = true;
    public boolean speed = false;
    public boolean memory = false;
    public boolean clock = false;
    public boolean potionHud = true;
    public boolean keystrokes = true;
    // Player
    public boolean toggleSprint = false;
    public boolean fullbright = false;
    public boolean zoom = true;
    public int zoomFactor = 4;
    // Crosshair
    public boolean customCrosshair = true;
    public boolean crosshairDot = false;
    public int crosshairSize = 5;
    public int crosshairGap = 2;
    public int crosshairThickness = 1;
    public int crosshairColor = 0;

    public static final int[] COLORS = {0xFFFFFFFF, 0xFF7FDBFF, 0xFF55FF55, 0xFFFF5555, 0xFFFFD84D, 0xFFFF77FF};
    public static final String[] COLOR_NAMES = {"White", "Ice", "Green", "Red", "Gold", "Pink"};

    public static FrostConfig get() { return instance; }

    public static void load() {
        try {
            if (Files.exists(FILE)) {
                FrostConfig c = GSON.fromJson(Files.readString(FILE), FrostConfig.class);
                if (c != null) instance = c;
            }
        } catch (Exception e) {
            System.err.println("[FrostClient] Could not load config: " + e);
        }
    }

    public static void save() {
        try {
            Files.writeString(FILE, GSON.toJson(instance));
        } catch (Exception e) {
            System.err.println("[FrostClient] Could not save config: " + e);
        }
    }

    public int color() { return COLORS[Math.floorMod(crosshairColor, COLORS.length)]; }
}
FROST_EOF_END
mkdir -p "src/main/java/net/frostclient"
cat > "src/main/java/net/frostclient/FrostHud.java" <<'FROST_EOF_END'
package net.frostclient;

import net.minecraft.client.MinecraftClient;
import net.minecraft.client.font.TextRenderer;
import net.minecraft.client.gl.RenderPipelines;
import net.minecraft.client.gui.DrawContext;
import net.minecraft.client.network.ClientPlayerEntity;
import net.minecraft.client.network.PlayerListEntry;
import net.minecraft.entity.EquipmentSlot;
import net.minecraft.entity.effect.StatusEffectInstance;
import net.minecraft.item.ItemStack;
import net.minecraft.text.Text;
import net.minecraft.util.Identifier;
import net.minecraft.util.math.Vec3d;
import org.lwjgl.glfw.GLFW;

import java.time.LocalTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayDeque;

public class FrostHud {
    public static final int ACCENT = 0xFF7FDBFF;
    private static final int BG = 0x90101820;
    public static final Identifier LOGO = Identifier.of("frostclient", "textures/gui/logo.png");

    private static final ArrayDeque<Long> leftClicks = new ArrayDeque<>();
    private static final ArrayDeque<Long> rightClicks = new ArrayDeque<>();
    private static boolean prevLeft, prevRight;

    public static void render(DrawContext ctx) {
        MinecraftClient mc = MinecraftClient.getInstance();
        ClientPlayerEntity player = mc.player;
        if (player == null) return;
        pollClicks(mc);
        if (mc.options.hudHidden) return;
        FrostConfig cfg = FrostConfig.get();
        TextRenderer tr = mc.textRenderer;

        int y = 6;
        if (cfg.username) y = usernamePanel(ctx, tr, 6, y, AccountManager.current());
        if (cfg.coordinates) {
            String xyz = String.format("XYZ  %.1f / %.1f / %.1f", player.getX(), player.getY(), player.getZ());
            y = panel(ctx, tr, 6, y, xyz + "  [" + player.getHorizontalFacing().asString().toUpperCase() + "]");
        }
        if (cfg.fps) y = panel(ctx, tr, 6, y, mc.getCurrentFps() + " FPS");
        if (cfg.ping) {
            PlayerListEntry e = mc.getNetworkHandler() == null ? null : mc.getNetworkHandler().getPlayerListEntry(player.getUuid());
            y = panel(ctx, tr, 6, y, (e == null ? 0 : e.getLatency()) + " ms");
        }
        if (cfg.cps) y = panel(ctx, tr, 6, y, "CPS  " + cps(leftClicks) + " | " + cps(rightClicks));
        if (cfg.speed) {
            Vec3d v = player.getVelocity();
            y = panel(ctx, tr, 6, y, String.format("%.1f b/s", Math.hypot(v.x, v.z) * 20));
        }
        if (cfg.memory) {
            Runtime rt = Runtime.getRuntime();
            long used = (rt.totalMemory() - rt.freeMemory()) / 1048576, max = rt.maxMemory() / 1048576;
            y = panel(ctx, tr, 6, y, "MEM  " + used + " / " + max + " MB");
        }
        if (cfg.clock) y = panel(ctx, tr, 6, y, LocalTime.now().format(DateTimeFormatter.ofPattern("HH:mm:ss")));
        if (cfg.armorHud) drawArmor(ctx, tr, player, 6, y + 2);
        if (cfg.potionHud) drawPotions(ctx, tr, player);
        if (cfg.keystrokes) drawKeystrokes(ctx, tr, mc);
    }

    // ---------- helpers ----------
    private static int panel(DrawContext ctx, TextRenderer tr, int x, int y, String text) {
        int w = tr.getWidth(text) + 10;
        ctx.fill(x, y, x + w, y + 14, BG);
        ctx.fill(x, y, x + 2, y + 14, ACCENT);
        ctx.drawText(tr, text, x + 6, y + 3, 0xFFFFFFFF, true);
        return y + 17;
    }

    public static void drawLogo(DrawContext ctx, int x, int y, int size) {
        ctx.drawTexture(RenderPipelines.GUI_TEXTURED, LOGO, x, y, 0f, 0f, size, size, 64, 64, 64, 64);
    }

    // username with the FrostClient logo on its right side
    private static int usernamePanel(DrawContext ctx, TextRenderer tr, int x, int y, String name) {
        int w = tr.getWidth(name) + 10 + 16;
        ctx.fill(x, y, x + w, y + 16, BG);
        ctx.fill(x, y, x + 2, y + 16, ACCENT);
        ctx.drawText(tr, name, x + 6, y + 4, 0xFFFFFFFF, true);
        drawLogo(ctx, x + w - 14, y + 2, 12);
        return y + 19;
    }

    private static void pollClicks(MinecraftClient mc) {
        long h = mc.getWindow().getHandle();
        boolean l = GLFW.glfwGetMouseButton(h, GLFW.GLFW_MOUSE_BUTTON_LEFT) == GLFW.GLFW_PRESS;
        boolean r = GLFW.glfwGetMouseButton(h, GLFW.GLFW_MOUSE_BUTTON_RIGHT) == GLFW.GLFW_PRESS;
        long now = System.currentTimeMillis();
        if (mc.currentScreen == null) {
            if (l && !prevLeft) leftClicks.add(now);
            if (r && !prevRight) rightClicks.add(now);
        }
        prevLeft = l;
        prevRight = r;
    }

    private static int cps(ArrayDeque<Long> q) {
        long now = System.currentTimeMillis();
        while (!q.isEmpty() && now - q.peekFirst() > 1000) q.pollFirst();
        return q.size();
    }

    private static void drawArmor(DrawContext ctx, TextRenderer tr, ClientPlayerEntity p, int x, int y) {
        EquipmentSlot[] slots = {EquipmentSlot.HEAD, EquipmentSlot.CHEST, EquipmentSlot.LEGS, EquipmentSlot.FEET, EquipmentSlot.MAINHAND};
        for (EquipmentSlot slot : slots) {
            ItemStack stack = p.getEquippedStack(slot);
            if (stack.isEmpty()) continue;
            ctx.fill(x, y, x + 62, y + 18, BG);
            ctx.fill(x, y, x + 2, y + 18, ACCENT);
            ctx.drawItem(stack, x + 4, y + 1);
            ctx.drawStackOverlay(tr, stack, x + 4, y + 1);
            if (stack.isDamageable()) {
                int max = stack.getMaxDamage();
                int pct = (max - stack.getDamage()) * 100 / max;
                int color = pct > 50 ? 0xFF55FF55 : pct > 20 ? 0xFFFFD84D : 0xFFFF5555;
                ctx.drawText(tr, pct + "%", x + 24, y + 5, color, true);
            }
            y += 20;
        }
    }

    private static void drawPotions(DrawContext ctx, TextRenderer tr, ClientPlayerEntity p) {
        int y = 6, sw = ctx.getScaledWindowWidth();
        for (StatusEffectInstance e : p.getStatusEffects()) {
            String name = e.getEffectType().value().getName().getString() + " " + (e.getAmplifier() + 1);
            int secs = e.getDuration() / 20;
            String time = e.isInfinite() ? "∞" : String.format("%d:%02d", secs / 60, secs % 60);
            String text = name + "  " + time;
            int w = tr.getWidth(text) + 10;
            int x = sw - w - 6;
            ctx.fill(x, y, x + w, y + 14, BG);
            ctx.fill(x + w - 2, y, x + w, y + 14, ACCENT);
            ctx.drawText(tr, text, x + 4, y + 3, secs < 10 && !e.isInfinite() ? 0xFFFF5555 : 0xFFFFFFFF, true);
            y += 17;
        }
    }

    private static void key(DrawContext ctx, TextRenderer tr, int x, int y, int w, int h, String label, boolean down) {
        ctx.fill(x, y, x + w, y + h, down ? 0xB07FDBFF : BG);
        ctx.drawCenteredTextWithShadow(tr, Text.literal(label), x + w / 2, y + (h - 8) / 2, down ? 0xFF101820 : 0xFFFFFFFF);
    }

    private static void drawKeystrokes(DrawContext ctx, TextRenderer tr, MinecraftClient mc) {
        var o = mc.options;
        int x = ctx.getScaledWindowWidth() - 76, y = ctx.getScaledWindowHeight() / 2 - 30;
        key(ctx, tr, x + 26, y, 22, 22, "W", o.forwardKey.isPressed());
        key(ctx, tr, x, y + 24, 22, 22, "A", o.leftKey.isPressed());
        key(ctx, tr, x + 26, y + 24, 22, 22, "S", o.backKey.isPressed());
        key(ctx, tr, x + 52, y + 24, 22, 22, "D", o.rightKey.isPressed());
        key(ctx, tr, x, y + 48, 36, 22, "LMB " + cps(leftClicks), prevLeft);
        key(ctx, tr, x + 38, y + 48, 36, 22, "RMB " + cps(rightClicks), prevRight);
        key(ctx, tr, x, y + 72, 74, 14, "SPACE", o.jumpKey.isPressed());
    }

    public static void drawCrosshair(DrawContext ctx) {
        FrostConfig c = FrostConfig.get();
        int cx = ctx.getScaledWindowWidth() / 2;
        int cy = ctx.getScaledWindowHeight() / 2;
        int col = c.color();
        int t = c.crosshairThickness, s = c.crosshairSize, g = c.crosshairGap;
        int h = t / 2;
        ctx.fill(cx - h, cy - g - s, cx - h + t, cy - g, col);
        ctx.fill(cx - h, cy + g, cx - h + t, cy + g + s, col);
        ctx.fill(cx - g - s, cy - h, cx - g, cy - h + t, col);
        ctx.fill(cx + g, cy - h, cx + g + s, cy - h + t, col);
        if (c.crosshairDot) ctx.fill(cx - h, cy - h, cx - h + t, cy - h + t, col);
    }
}
FROST_EOF_END
mkdir -p "src/main/java/net/frostclient"
cat > "src/main/java/net/frostclient/FrostMenuScreen.java" <<'FROST_EOF_END'
package net.frostclient;

import net.minecraft.client.gui.DrawContext;
import net.minecraft.client.gui.screen.Screen;
import net.minecraft.client.gui.widget.ButtonWidget;
import net.minecraft.text.Text;

import java.util.function.Supplier;

public class FrostMenuScreen extends Screen {
    private static final int W = 150, H = 20, GAP = 6, PH = 236;
    private static int tab = 0;
    private static final String[] TABS = {"HUD", "Player", "Crosshair"};
    private int item;

    public FrostMenuScreen() { super(Text.literal("FrostClient")); }

    private int y0() { return height / 2 - PH / 2; }

    @Override
    protected void init() {
        FrostConfig c = FrostConfig.get();
        item = 0;
        int tw = 80;
        int tx = width / 2 - (tw * 3 + GAP * 2) / 2;
        for (int i = 0; i < 3; i++) {
            final int idx = i;
            ButtonWidget b = ButtonWidget.builder(Text.literal((tab == i ? "§b" : "§7") + TABS[i]), x -> {
                tab = idx;
                clearAndInit();
            }).dimensions(tx + i * (tw + GAP), y0() + 22, tw, H).build();
            addDrawableChild(b);
        }

        switch (tab) {
            case 0 -> {
                toggle("Username + Logo", () -> c.username, () -> c.username = !c.username);
                toggle("Armor HUD", () -> c.armorHud, () -> c.armorHud = !c.armorHud);
                toggle("Coordinates", () -> c.coordinates, () -> c.coordinates = !c.coordinates);
                toggle("FPS", () -> c.fps, () -> c.fps = !c.fps);
                toggle("Ping", () -> c.ping, () -> c.ping = !c.ping);
                toggle("CPS", () -> c.cps, () -> c.cps = !c.cps);
                toggle("Speed", () -> c.speed, () -> c.speed = !c.speed);
                toggle("Memory", () -> c.memory, () -> c.memory = !c.memory);
                toggle("Clock", () -> c.clock, () -> c.clock = !c.clock);
                toggle("Potion HUD", () -> c.potionHud, () -> c.potionHud = !c.potionHud);
                toggle("Keystrokes", () -> c.keystrokes, () -> c.keystrokes = !c.keystrokes);
            }
            case 1 -> {
                toggle("Toggle Sprint", () -> c.toggleSprint, () -> c.toggleSprint = !c.toggleSprint);
                toggle("Fullbright", () -> c.fullbright, () -> c.fullbright = !c.fullbright);
                toggle("Zoom (hold C)", () -> c.zoom, () -> c.zoom = !c.zoom);
                cycle(() -> "Zoom Level: " + c.zoomFactor + "x", () -> c.zoomFactor = c.zoomFactor % 10 + 1);
            }
            default -> {
                toggle("Custom Crosshair", () -> c.customCrosshair, () -> c.customCrosshair = !c.customCrosshair);
                toggle("Center Dot", () -> c.crosshairDot, () -> c.crosshairDot = !c.crosshairDot);
                cycle(() -> "Size: " + c.crosshairSize, () -> c.crosshairSize = c.crosshairSize % 12 + 1);
                cycle(() -> "Gap: " + c.crosshairGap, () -> c.crosshairGap = (c.crosshairGap + 1) % 8);
                cycle(() -> "Thickness: " + c.crosshairThickness, () -> c.crosshairThickness = c.crosshairThickness % 4 + 1);
                cycle(() -> "Color: " + FrostConfig.COLOR_NAMES[c.crosshairColor % FrostConfig.COLORS.length],
                        () -> c.crosshairColor = (c.crosshairColor + 1) % FrostConfig.COLORS.length);
            }
        }

        addDrawableChild(ButtonWidget.builder(Text.literal("Done"), b -> close())
                .dimensions(width / 2 - W - GAP / 2, y0() + PH - 28, W, H).build());
        addDrawableChild(ButtonWidget.builder(Text.literal("§b❄ Accounts"), b -> client.setScreen(new AccountScreen(this)))
                .dimensions(width / 2 + GAP / 2, y0() + PH - 28, W, H).build());
    }

    private int nextX() { return width / 2 + (item % 2 == 0 ? -W - GAP / 2 : GAP / 2); }
    private int nextY() { return y0() + 50 + (item / 2) * 24; }

    private void toggle(String name, Supplier<Boolean> get, Runnable flip) {
        addDrawableChild(ButtonWidget.builder(label(name, get.get()), b -> {
            flip.run();
            b.setMessage(label(name, get.get()));
        }).dimensions(nextX(), nextY(), W, H).build());
        item++;
    }

    private void cycle(Supplier<String> text, Runnable next) {
        addDrawableChild(ButtonWidget.builder(Text.literal(text.get()), b -> {
            next.run();
            b.setMessage(Text.literal(text.get()));
        }).dimensions(nextX(), nextY(), W, H).build());
        item++;
    }

    private Text label(String name, boolean on) {
        return Text.literal(name + ": " + (on ? "§bON" : "§7OFF"));
    }

    @Override
    public void renderBackground(DrawContext ctx, int mouseX, int mouseY, float delta) {
        super.renderBackground(ctx, mouseX, mouseY, delta);
        int pw = W * 2 + GAP + 24;
        int x = width / 2 - pw / 2, y = y0();
        ctx.fill(x, y, x + pw, y + PH, 0xD0101820);
        ctx.fill(x, y, x + pw, y + 2, FrostHud.ACCENT);
        FrostHud.drawLogo(ctx, width / 2 - 50, y + 4, 16);
        ctx.drawText(textRenderer, Text.literal("§b§lFrostClient"), width / 2 - 30, y + 8, 0xFFFFFFFF, true);
    }

    @Override
    public void close() {
        FrostConfig.save();
        super.close();
    }

    @Override
    public boolean shouldPause() { return false; }
}
FROST_EOF_END
mkdir -p "src/main/java/net/frostclient/mixin"
cat > "src/main/java/net/frostclient/mixin/GameRendererMixin.java" <<'FROST_EOF_END'
package net.frostclient.mixin;

import net.frostclient.FrostClient;
import net.frostclient.FrostConfig;
import net.minecraft.client.render.GameRenderer;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

@Mixin(GameRenderer.class)
public class GameRendererMixin {
    private static float frost$zoom = 1f;

    @Inject(method = "getFov", at = @At("RETURN"), cancellable = true)
    private void frost$zoom(CallbackInfoReturnable<Float> cir) {
        float target = FrostClient.zooming() ? FrostConfig.get().zoomFactor : 1f;
        frost$zoom += (target - frost$zoom) * 0.25f; // smooth zoom
        if (Math.abs(frost$zoom - 1f) > 0.001f) cir.setReturnValue(cir.getReturnValue() / frost$zoom);
    }
}
FROST_EOF_END
mkdir -p "src/main/java/net/frostclient/mixin"
cat > "src/main/java/net/frostclient/mixin/InGameHudMixin.java" <<'FROST_EOF_END'
package net.frostclient.mixin;

import net.frostclient.FrostConfig;
import net.frostclient.FrostHud;
import net.minecraft.client.gui.DrawContext;
import net.minecraft.client.gui.hud.InGameHud;
import net.minecraft.client.render.RenderTickCounter;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(InGameHud.class)
public class InGameHudMixin {
    @Inject(method = "renderCrosshair", at = @At("HEAD"), cancellable = true)
    private void frost$crosshair(DrawContext context, RenderTickCounter tickCounter, CallbackInfo ci) {
        if (FrostConfig.get().customCrosshair) {
            FrostHud.drawCrosshair(context);
            ci.cancel();
        }
    }
}
FROST_EOF_END
mkdir -p "src/main/java/net/frostclient/mixin"
cat > "src/main/java/net/frostclient/mixin/MinecraftClientAccessor.java" <<'FROST_EOF_END'
package net.frostclient.mixin;

import net.minecraft.client.MinecraftClient;
import net.minecraft.client.session.Session;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Mutable;
import org.spongepowered.asm.mixin.gen.Accessor;

@Mixin(MinecraftClient.class)
public interface MinecraftClientAccessor {
    @Mutable
    @Accessor("session")
    void frost$setSession(Session session);
}
FROST_EOF_END
mkdir -p "src/main/java/net/frostclient/mixin"
cat > "src/main/java/net/frostclient/mixin/SimpleOptionAccessor.java" <<'FROST_EOF_END'
package net.frostclient.mixin;

import net.minecraft.client.option.SimpleOption;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.gen.Accessor;

@Mixin(SimpleOption.class)
public interface SimpleOptionAccessor<T> {
    @Accessor("value")
    void frost$setValue(T value);
}
FROST_EOF_END
mkdir -p "src/main/resources/assets/frostclient/lang"
cat > "src/main/resources/assets/frostclient/lang/en_us.json" <<'FROST_EOF_END'
{
  "key.frostclient.menu": "Open FrostClient Menu",
  "key.frostclient.zoom": "Zoom",
  "key.category.frostclient.main": "FrostClient"
}
FROST_EOF_END
mkdir -p "src/main/resources"
cat > "src/main/resources/fabric.mod.json" <<'FROST_EOF_END'
{
  "schemaVersion": 1,
  "id": "frostclient",
  "version": "${version}",
  "name": "FrostClient",
  "description": "Clean, smooth client HUD: armor HUD, coordinates, FPS and crosshair tweaks. Press Right Shift to open the menu.",
  "authors": ["You"],
  "environment": "client",
  "entrypoints": { "client": ["net.frostclient.FrostClient"] },
  "mixins": ["frostclient.mixins.json"],
  "depends": {
    "fabricloader": ">=0.16.0",
    "minecraft": "~1.21.11",
    "java": ">=21",
    "fabric-api": "*"
  }
}
FROST_EOF_END
mkdir -p "src/main/resources"
cat > "src/main/resources/frostclient.mixins.json" <<'FROST_EOF_END'
{
  "required": true,
  "package": "net.frostclient.mixin",
  "compatibilityLevel": "JAVA_21",
  "client": ["InGameHudMixin", "GameRendererMixin", "SimpleOptionAccessor", "MinecraftClientAccessor"],
  "injectors": { "defaultRequire": 1 }
}
FROST_EOF_END
mkdir -p src/main/resources/assets/frostclient/textures/gui
base64 -d > src/main/resources/assets/frostclient/textures/gui/logo.png <<'FROST_LOGO_END'
iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAAgUklEQVR4nL2beXxVxfn/3zPnnLsn
NwkhhBDCprIvsiqighWwVqv92oBrtVqx6q9iv63WDUPcqEtr61aXarFW1ODys3WXCoii7GsIm2EP
Ifty93POzO+Pe4MiAbHa37xeN3nl3tw583zmmWc+83megf9y01qLCq2NGSu1VaG1UVqhjSP9b2mF
Njr+t2yhNsu0lv/t8Yn/RqdaazF7EQYTUeVCqK9/Xqa1zGlpyd65M/13Tg607W9PPjy+JN5JZ6Ls
KH191/a9AlBaoY3SUpgmhNvxXtnGljxlek9Urj5ZGuZxhiVLtDIKDS9F2kYDCBOhHNo07nbXpkUI
e71ErTelWDHr+MCejr601mI+yGmgEEJ/H2P+XgAo01rOBi0ygyrbGi3WyMlI43zDsE7xZdHFlw2u
nX4lWiHWHEEYEjRopbECAbIKBEKC5QM7DvEWYq7trtWu8waCd8pP8G3qeGaF1sZXgf5P23cC4OCM
ZAZS/oU9WWl9mWFa54W6kq01tOy1qdu6Ue3fuEIdqNpEpG6viDW3iEj9fiENM92PcvEEs3R2UQ/t
DeZSOGiILhw0SnQbOMzI65WNJwCRehw7aS9E63+Q9LxcPkSkOmLEd1ka/zEAX52B8i16nLbsuz1+
a7I/F1p2u1R/+qG7bdF77Fm5VLYfqBGpWBQhJEJKpGkiTQvo8GKBVi5uKoVGox0Hw+sj2KVAdx8y
Uh0/aarud+pks6B/PsqBWLOz0U2p++7q733p62P5/wJAmdZmuRBOWZUuwrTvMb3WpaF8rP1V9Wpt
xVy95YN/yfrtVUIrhenzY3g8SGkAGq3J/NaIQyAAhAQBAoHWCte2cRJxlOuQ06NE9z3tTDXqwqvp
NXaA4aQg0W5/KGxrVll/sezry/C/AoDWWswGUS6EmlVlTzU94rnsIqOooTrC8r//xV3/+otG695d
mH4/lj+ASFuDVgqtvp2XCsP4yuAETipBKhrFl53DgCk/VuOuvIHeY/vK9jrluI6+qfw480+QDsTz
px27NxwzAGVay461NmuLPdsbMMs8Qah6b7Hz7wfuMA5sXi+8WWFMrxftKrROv1KRGIbHxPL50foY
J0cIUpE2ECaegP/ge1IaKNch0dZCsEsBE66/2R1zyVXSG0JEG52K1rrotQ+Pz2n6NkvimADoMP6m
Kp0VtJw/ZXUzr4w04H70hzKx8oUnpZAGnmAI5ToIBNI0iLc0c8Zv76FL30I+f/Y5atatwPT50fro
niCEwLVT9J98HiOnl7Km4jU2/HMegZx8lGujtUaaJm4qRTLSxvGTztZnzf6TWzSkq9myz13hJo1L
7hksth0rCN/ItDqMv2W9zg1aakF2d/PKuq0N9ktXnW98/uyfpScQwvL7UXYKKSV2Mk68tRlvKIt+
p53FiaXn4c/tgmOnQHwz3kIapKIRCgeOYPh5EykZeyoAqVg7TiqFkAbKsZGGQSA3n+2L3xcvXDLF
3PTeKierwBhj+d3PZ23QY6YJ4VboI7POYwIgs+Z12T4d8Pjc98NFcuy2hRvsudPPtHavXEqwS1eE
FAghkJZFtKmewkEnMuqiGQTyupLXuwc1G5qoWb8Cyx/4xtnPPBNpWnzxyQe01Lp0HzIK0+Ol17jT
CReVkGhrRkgDRDpQ+sO5RBvrefkXPzaXPjPPDXYx8syQ+/4dVXrosYBgHu3D2Yswys+Qzh2bUk/k
lZhjti5cb8+/frqVaGvBlxVGOQ7JaHuGzCiGnDOdH93zMFp5ye83EG/IZNeyzUQb6/EEQwhAKQVH
iAVCSoQUmD4fjTu20lYbJa9XL3qMGMfZdz+BP9tgwf33svbVuUjDxHVsPIEgpteHch3emz3TANzx
V1+c237AefGWTXpSJTRrrcWRdocjekCZ1mb5JOHcvjE1O7enefmBzQ326zMvsxJtLXgCofR6RDPh
l7cw+uIryenZk6zCYrzZAYSEE6ddilZQs2ElbjKBdl1izU0ox+50KQghsOMx4s0tSMMkUn+A+q2V
WH6TM2+5H384jOnPoqVmN8p16DZgCH0nnJnZYVxkJg69N3umUfnWp05OsTnUFPbL5VKq+Uexs9NF
2RFAbt1kTw5myw+Uo5wXryw19678FG9WGKVc3GSCnJK+XP/BJ/iyIVIPtVVbyS4sxvR50UrjCUhe
mXExO5ct5n/+/BLR+l18/twTtNXuw/B4DnqCEBInEado+BhOuupKmnfV8/as65h6x8Oc+qvrSbaB
MBR1m7exd82n9D75NLoNOA6t4LEzRxOpr8WwPJkAauMNZXHZ39+1e4wosZp2O+X3DrZmly1MT+g3
ekCZ1rISdNkOXegxecETkPrfD82Ruz5bmDbeTfchDZNUpJ2K669iwQNPsXftOgr6n0B2YQDLZyAN
STKapH57Fbklfel/5kSG/uRytHYPh10IHDuFP7cLJ5aeR99Tz8KblcPOZYtwEhrXtgFJ8cj+nD7z
SnJ69mP3yrUsm/s0hmkdZFNaKQyPl2hDHW/feYMVqbddf1jcefsW+8zyScLpLB4cFgMGg5gmhHvb
htTvC46zuq1741Nn5QuPmv7cLgeNR2uEaRJvbabq3TfZ9PbrWP4A+f36UzhoGEPPu5jiE8fgy/Iz
6Oyf0rxnB75szdYFi2ndtxtPMOsQYqS1wvL7qVm/gpoNTeT16k5OjxKElJnPLFpr9rJn1afsXb2M
Xcs/oa12H3Y8hicYOsSbtOvgC+ey87OFfPrU42LqHTeKRLvzeJnWgytBfT0eHAKA1loKIdxZVdFR
3mx5YcOOVvffD/zOELKTWJnZj33hHAQC5TrUbtrAjuUL2fLh2/zynZVIM8y4K26gadcXuI6gdtMa
3FQKEZJo1CF9GZaHaGM99ds3UXDCBPqM/wGDfzQNb8jgQNUe/n7pFBp3bgMgmFuA5fNh+fydBlXl
Ovhz8lj2tz/KvhPOcI87bdgJzVX2NfcO8jw+OO0FB/nBIUtgdkcHyvOHYK7hXfb8sxyoWi88wVDn
VFZrtNKkYhHyevXjshfe4oez/ky4qJhP/vIQWrt4s7LpMWIkqfZ0QJSm1SkjFELiJhPs37ASJwUT
rr+NwsEjsOMOC/84m0RrM8N+fDE/vPNPhIt64tqpI+8oWiMMEzsWY8nj98pUHG1a8u6yzW350zJe
cJgHdAS+26vsiaFc4/TaqiZ3/evPG97sL9d9Z62DuXU9YQj9zxzHgKnjOH3mDdSsqybeksL0WKAk
bfubqduy8YhssGP/37duJXZC48vKRhqa5t319D3lTKbcfj95ffIJ5ULjjm2sf/0FfB4/Wnc+Nu06
eLPD7Px8kdj20VJn2Hnjcxt3eK5HiPLZWpuAcwgA8zsMUnqGP0ew6OHndeveXQTyuh4VAK1cvMEs
qpd8yJNnn03xyJPoM/4MioefRCDPxI6nBY9ktJ1kpBWZEUEOB0Bh+v3UVq0lWt+OLzsESLoeX0j3
wRfRvCfKxjffY8+qT9i/cQ1WIAj6m5iuQLuKFS88IvufOV4L0/zZH3brB34DCbQWCJF2hY7AULYx
UigDwW3KSQTnXjiFxp3bhen1w7EwOKVwkglcx8YwTMLFveg5chzDL7iM4pHjkCZ8eG8Zy+Y+QiA3
/zBQhTSwYxGKRozlwqfmY3q9tNbsYdeyJWxb+D77K1cTbajDSaXwBAIYHu8RCdXXMEC7ikue/0D1
GddfttUmz7l7kO/tUq2N+UK4EmA2GAAO1tSsboSqP/1E1W/bJCx/4JiMTxsg8QRDBHLy8ISyiNQf
YPXLz/FO2a9JtrehbM34Gf9LbklfnGS8EzKkUa7DhGtvw5/jJdHayvzrL+bNm2ewbdG7JNpa8ARD
BPPyMY/VeEBKk2R7K1XvzldWAK01pUD6B18GQQUIpJimNWxb9DZaqfR5/ls0rRTKddP7sWkS7tGL
+q2VrJo3F9MnCOaHOfX620nFohmBJAOeYZJoa2HwuRfS+6RxAKx6ZS4HNq0j3L0Ybyg7HTyVQrnO
sR+rSVNv0+dn52cfGa37HWF6vFN/t7IpPE0IV2stpNZalAuhypa25Fpe6+SWvSn2rFwqTZ8fpdwM
Pz/8PCGkgZBHPktprXFSSXzhHFb+4wkatu1GOZoh555Pv1OnkGhrOdivdh28wSxOvup/sXxQW7WT
VS8+iS8nF8dOoZV79PNDZ9RaSjJqDKbPT0P1FlGzvlIFulAoLWs0wHyQsoMnJ0Pekf4wOXVbq1T7
gX3C8HgQpPl5MtJ6KAhCkIy0YsdjCOMohy2tMUwP0cY6ljzxAEIKpCE5+erfIE0TtEKaJonWZsZc
/iu6DeiLcgTL5z5GpG4/huk5qqsLw8COx3Bt+5DJEFKSikYAfVBIseMxajYsV56AxjA9pwEsWIWU
C1alATCkHu3LRuzfuEqlolEM00My2k6vcaczcvrVxJrqkYZ5sPMTp/2CXuMmEmtqyAicnTflOvhy
8qh862V2fr4MDfQZP5Zh519Kor0VZdvk9urHyOlXIk3YsXQ5G958kUOYZyetA7juQ0YTKigkFY1k
vFWSirbT++QzQIj04Ys0z9i3boVwHYGQYixAczVKbmlPb0rSMAe6NtRWrRPCMHDtFFndunPeg89y
7pz7GHXRNcRbGnGSCfqcPInzH5rDeQ8+Sc+R44m3NB4VBLRGGiZLHr8HN+XgJBUTrruZnKKeJFoa
OO3628kpziXekuTjx+7OkK4jxx9pWsRbmugxbCwX/fUVSh+vwJ+TBxrizY0M/58r+NmLLzHltgdR
jgNoDK+XpuqtItqQQlpWn18v3e2fX4qSBfWZXVlQohyI1h1ICxymSaypgY8fvRcnBefMeYCRF84g
FY1QW7WWZX97mbxeYaY9+RI9RpxEvLkxfSLLxIyvvgC82WH2rFrKutcr8Pgl4eKuDJx+DV1GnU7/
c85HCtj84TvsWfkpvnAuoA/rR0iJYXmINzfSY8RJTHvqZbK7BzhQtQ6tFLHmBkZd/EvOmfMArg11
WyszwglIwyDe2iiS7RohKMqWAQshtDmoEl22Q/tw6RZvsYk11wtpmmilMD0+lj//KMn2Ns6+6wHO
vvv3CCH4fO6fefOmq0i0tTH+mhlM+8s85l93MbuWfZxWfjqjzUKgtWbhH26leNwEivv25MZfXIr7
07OoDUo2bd3PRw/8Dq018dYmUJ3QZSmx4zF6jTuN0ifmEeoaZtHDT/PeXTNBCE76+Ux+WD6HZHuM
t++4iXWv/Y1QQXe0VmmpLRajvW6vLhzUz2oPeIqANrO8XKg5F7T4k6FwSaw5RaS+Vkgrzde1UmQX
FtNYvYWq999n2HnnM2XWHDyhLPZvWMkXS96neORJlIwZxgWPzOPDOTeTaG1BmmanW5VhmMTamtn/
2ULumHA5BSIEJVmkgFvfW09WrxPoMfwk3E7WvhAC5Tj4wjlMvvUBQl3D7F6xni+WvM/xE39I96Gj
mfjr29AKqt59j9aaavKPG0S0sQ5pmEjDINneJlpr96qSMf18st4qBjYLgLI1zTkyO2dHMhbLefZ/
TtbxliZhWB5cO4U/J4+r/+8KTJ+FctK5C9MnDvIjJ5GhEKbA8BydnUoBUQWTsmByF3AUaDSWFGyP
w9wD4JNH5zjCADcFytGAwvQZGe8AJ6HRWqCVQzDf5MXLL+WLj9/HmxUGNKlohGlPv6EGTRkv2/bE
J949LLD40HOu5vCnC4Hp9WB6wXY0ytWAwPJlvuJKXEejHIXll0irU6p/EADThVDw0JnVgN8DHh+Y
4sjfT2uKYLsKhMSwDCx/etxOCrSrM5qiieXLcIHO0BQcPAWZAElDCJ/A1EofXL9aa4SUKNvm3w/e
wYAp59FjxCj8Acmmdz+gtnI1QhoM+tE08vv0QinB8ufnEm9uPPISkAbRWITmocMY/fMfYcmOaC94
Y8kGPnjjX4Szs3Ddw92oYwn4c7swcvoVSFNTW7WVze+9jjAMCgeNYOBZU7Djiu2LF7Nv7RLa9u/B
8HrTMSATg7TrpL3FFmYaAK2Ft7LORtNsBcyQJ5Sl463NAgTSMGndu4toUwPdBp6ANyhZ+eI83p51
PclYKz+88zHy+/ZEK5cP7r2N5XMfxfD4AHX4NHawNeVS/Ny7PF8Pp/gUHjRrEybb/F3Z9tY8mndX
Y3h96an++qwhcVMJGr7YzNl3/Z6ux/WmOhji/Xt+jScQ4px7n2TMzy6kx/AhbPjnS+xbuywdBJVC
ozG9XnyhsHASOEKoVgCzdD6yfFq3yKwtzhfZhd6e4cIS3bRjO5Y/QCoWZfw1NzF1Vhlawzt33saK
F58kkNuF8//wPGMu/TGNO9t47YafsXv5x2QVFqf9sROv69hWR15yLcMmn8K+JMx6/X3qt2xg4m9u
oahPIWfcNId/3nwlgbz8zP7diesCq19+htaaPfz4/ic585ZfEerajQX338q7s2fSWL2VybffSenj
TxPK78raV+dien3peJado/N69xeJduJuKrktDWlH31o1CwGeUBZfqoyagv5DkCa8devNLH/hcXzZ
ORiWh24DhtBaE6PimunsWrYYf24+yrFRjoNyv/ZSLqlYhFDXboyf8WsSEYVIOqx59iFWP/dHItW7
SCU0g354Nr3HTyLWVI/W+vB+nPTLn5PHtoVvUXHtdBp3tDL28mn0GDYGISVL//pH3rr1ZgwTTv0/
t30JptZY/qA2vQC0+ny5LloLM7cvEnBd115v+ayfFA4arqvefZV0ZDf54L6bqHz7VXZ+9m8CufkA
xJobmX/9hQS7dGPf+uWZh9iHz1jH7EuDZKyFM357H+GirgCs+MeL1G6pRAjBkicf5LwHHkO7BhNv
uJMX1yxLH4CO0JTjEMzvxp5VS3nzpl+SU9yb6qUf4Q1l4wmEWPXSU0jTpHlPNe0H9uPLziHR0kRu
r+N1dqGPtlp3211DzEhphTZk9wwVdl1RacehcNCJwvT60skG0wKt2fnZRweVXK0UnmCISN1+9m9c
iS+c27m7dniWlKRiEQoHj2DEBRfhpBStNfUsfep+TK8Xbyibyn+9wvbFS0BA8cghDD5nOom2dILk
iCDYNoG8fHYtW8Sair+S1i1dlOsQyOvK6leeYdeyxXiDIdAapVy6Dx6hTS+4jlMJkNuMlLMnphVS
6eql8WZihQOHG8H8Au3aqQ4T+LooqpXCsKw06+skYn8NApTjcPrM8kyaXPLJXx6krXYfpseHzpwI
F/+5DDflYCcUE669iezCHjipxFETqtp1sfwBvKHwIdudVi7eUDiTj9RorTAsDz1GnCTcFGjX/Qig
+wloKYTQZVpLa0RgfzLubsjtnUXh4JHKScQRQgK6U2rbwRQ7t1kgpIHh8ZJobWLwudM57vRTQcPe
1RupfOsVfNk5aXFDKTyBELWVa1n72kuYHkm4qCvjr/kddjx2MONzRBAyqbHD308LMwiBk0oS7lGi
i4aNMKJNtNk2ywBmT8TtCILp4gcn9ZrHD8dPOlsr1z3qgw+3WRw8LivHJtneSrThAL6cXE6Z8VuU
m56JRY/chR2PHqIvKOViBYIsfep+WmvqcVOaERdcREH/obTu24XrOOnaIuPoIkxnTUoDOxal5+hT
VJc+QZ2K2kseHBWsKUvnQPRXJTEcQ74Zqcfpd+oPjJwevb7RBb9iPU4qSbSpgVQ0gi87h+Mnnc05
9z3BFS8tIFxcgukRbPznG1Qv+RBfdu6hs6Y1psdHW+0+ljzxAIZXIKTk3PseZ/TFVxPK70Yq0k6s
pYlUNPKtym20VpgeL4OmlkJaJn61A5v0G5lWprVk9mzc6bcvyCuxJr4682a1et4zRiDvcAX3UNsF
rmOTU9yHvqecRs9REygZcyq5JUHcFCQj4KYUCIcXLjuHus3rsQLBIxiRZp8/e/EjuvTpBQg8AYg2
2exbt4wdSz9i7+rPadmzCzse/cbJEVJix6IU9B+ir6h4H+UYjUm3fdCcE7LrO5Twr/qTLC8vVyjn
r8pBjJx+Nb6cnKMan35K2sW6DzmR0kfvYciPz8K1kyx5fC771u1A67SQaXhM/OHcI4sdQqDcdDzw
BrNQrsZJOrTXxWnbv4/+P5jAuXPu5JfvvEPfUyeTjLZ3qlUe2qXEtVOMvHCGm1VgCCeefHPOCdn1
FVobHfnBgwDMBresrEwaQf/rrbXOtt7jjjcGTD5fJVqPvh1pnY7Ee1d/zttlj/HiFZfxxOThbHhz
Hjk9C1AuWH4Pll9SMvoUXDvVuYiZSZEX9B9KVvcuSEMiDRN/jkXlWxX8ZerpLJjzCFsWLKN+60YM
y3NUdbhj++02cJgecu55MnLAdQyTh9BalH6Fq37JBIXQg2fPFuV9REK56nbXVpx01Q06mN8V90j1
PUIgMypNa80e3r3rRjb+6xWEITm7/BG8WUGUrfjik0VoF7oPHY3h9XWaGhMZ/a5o6Gh82bB7xTIi
DXWAyUlXXke8tYV37p7JC5edQ9OuL/AEQggpjrgMOlJ2J1/1W5Xd3Svj7e5T5QN8mytAiq9Ulh4S
UqcJ4ZZqbdw72Du/7YBa3GtMH2PCdbe7yfbWQ3T8DuOVYxNrbkxvM0XFnPTzG/jpo//gylcX0fX4
AWgXqpd8wII5N2MnXPL7DSDYpXNAtVYYHg+Fg05EmpoV//gLnz/3J6Sh8YZCnP/QXzn5ipkUDhqK
a6eINTeQaG1Jk7Cv9SUNk1hzI0POvVCP+Ok5orXGaVbaM0unZ/8Q9A/z7QrQQmshN9u/aa9zlo39
2eVUf/Kh3r74XeEP56VjghC4qRThop6MvPDnFA0bS7cBwwkXCVIxSEXBjjuYPpMN/5xH065qWvbs
p9fYYoqGjWHLh//El+1NF0tkwMzs1fSZMJFEKzTvrmbvms857Ve3Y/n8FJ84hj7jx5CKQ836dexd
8zk1G5azb81KEq3NCNNMZ4WlxE7EyenZm0m/KXelhenYetbvh4nmkZ2Uzh22qQohVAXIuwd6ViXa
9W89QYyzyx92wkU9sRPxLwOPANexGXfFDEpGj6B1XzUL//gM1Z+sAZEukhQG9Bg+jlSsjS8+fo81
898k3tyIaXWi92sQwmDDG8+zZcEimnZso/vgE/HnBNBK4yQVbbUx6rZspXjEcM68+RqmPf4snlBW
JlALOoKrcmzOuvNRp/vAfLO1xn7t3kGex49UN3jEfaSjHviOTc6rXfoYF1S9t9p56RfnmtK0kIZx
8FzQc/QpxFsaqK1cS/5xA7nilQVoJRDSxBOA6iWf8fI1P8Hy+0m2RY5cNZpZUuly2DCJ1mYm/rqc
02+cSaI1k18IG3x4391s/uA1jj99Kr5wActfeCxjRPrwFqmvZcodf1KTbrxKttU6O3wec9QtJbRk
JvewqHlEWjUb3DKtZTBoXN2811nZ/wcjzcm3PeTasWg6b5hJQlR/soADmyuRhoXp9dO8azvBLiar
5j1DtCFKwYChhLp2y6g5OQf5+WEtUx8QyM1DGAaG10fR0NEICavmPZVOsbfFaK/dS8uePayc9xyf
PPn7TD1yugI92lDH6EuuU6dcfRXRJqfZdsxpt/YSzbPhiGVyR9zfhBBaay1EL9F8+2Y9rb3BXTX+
Fxflaq3d98tnGqbPj+nx4g1ldXyD2o2rmXflBYy88Oesfvk5eo09lR4jTqBLnxPY+dkiDMt7dBan
NUqp9HG3S1fyjxtIst1h7atzaa3Zzf7KtexZ9QnBLgXp6pRM5TlApL6W0Zdcq869736FwIy3MGPO
cLGyw5OP9MijEmshhKrQ2rh3gNjhRo2p0Sa3+ZQZFxvTnnrN8YayDyY4O7Q2TygLOx7h0ycfIlJf
S93mDeR0k/SbMAXl2Md0thAirf0XDRtD0dA8mnbuI9JwgFUvPU3tpjUE87pmRBcXIQVOMkkqFmHK
HX90z7n3AQmYkXp3xpzh1qvfZPw3AgDprbFCa+PuoWKFHTN+EG1y1wz/yWnmpX9/2+45ejzRhgMH
C6a0UgjDxJedg5QGu5Z/zLo3F1Fbtfbgef0bm9aYmezPmvlv8sXH75GKtOMP56aLotxMxtowiDU1
EuxSQOnj851JN15tOCnVHG1k+r1DzGcqtDa+yXj4FuXyHVH0lvU61xtwX8oqMKZG65X69OmHWfbc
IzKViOLLCqczQF/RCFKxOGgHTyj7mIsahBDYiThuysETCmSO5R2p8DTDc22bIeeW6km/LXcLBxSY
7XXONidiXnL3ULHiWGb+WwMAUFGhjWmZywgddwb8ObBt8Rp3yaNz5M5lHwvtuniCIaRhfoXxiWOb
/a8OLJP310ofrBe0YzFcO0W3gUP1yVfdqIb/9HzDsCDaYFckGq3rfj9ONH4b49Mj+5btkFsj2+yp
huQPwXxzsB2HbQsXOyv+/oTcs+pzmWxvw/T5sXy+g2f4tDrToRp3lrAQB6/OiEw1uJtKkorFMD0e
CvoP1iMv+oU75JxSM7u7SaTerVM298w+3nwUvv1tkf8IgI7WUXtbtlF7hNe+RlryjlBXoyAVhd2r
K9Xmd15V1Z8tko3VW6Udjx/M7ErTzIgb5iEgfFlek748pVwHw/IQLirRJWPGq4FTf0KfCRONrK4Q
aSDlpFJPgeee8uNE3X96X+g7AQCHIn7ret3N409dKw1zuj9HDvAEoHU/1GxYrWrWr1T71i0XjdXb
RbylQdjxOMlIm+hY21pnkhbZYW35Qzqvdz/dfdAo3WPEWFE0bJTRpY8fNLQ3cECn7H9paf25/Dix
Eb77/cHv4eKkFhX6y7uDv9qqvV1NZ6rr6vMN05rsC1PsCaQvTEYbIdEeIVJXR1vtXpUuk0lLYr5Q
WOT17idMr5+sQonlTef7Ys20uba9UOC+aQnnndv7ZR2AzD3jUtR/MuvfMwDp9vVLlAD3V9VnxURo
jNLyNCGM8dIyehoWhWiyA3nIjrgoJKRi4CRoVS7t2nW3KW2vNw2xWCl3RfkJwb0dfVZobVSC/r7u
EX//l6e1FhUZfvF11yzV2hjf0pJVt8coDGRZhZGWdLD2hUxibSoSyEtt398YSz09ukfsq98r01qy
CDl7Iu53nfGvt//K7fGO1uEVlSA2zUcfa4QurdDGoFIEi4BFqPLy7//WeEf7f9kWMLWQATJoAAAA
AElFTkSuQmCC
FROST_LOGO_END
echo "FrostClient project created. Next: gradle build"
