// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//
// Minimal LWJGL 3.3.3 + OpenGL 3.2 Core Profile verification demo for SiliconForest.
// Exercises: glfwInit, GL 3.2 core + forward-compat context, 854x480 window,
// GLSL 150 spinning coloured triangle, FPS reporting, key/HIToolbox callbacks,
// GLFW_CURSOR_DISABLED pointer lock / warp / delta reporting, and OpenAL alcOpenDevice.

import org.lwjgl.Version;
import org.lwjgl.glfw.GLFWErrorCallback;
import org.lwjgl.glfw.GLFWVidMode;
import org.lwjgl.openal.ALC10;
import org.lwjgl.opengl.GL;
import org.lwjgl.system.MemoryStack;

import java.io.FileOutputStream;
import java.nio.ByteBuffer;
import java.nio.FloatBuffer;
import java.nio.IntBuffer;

import static org.lwjgl.glfw.GLFW.*;
import static org.lwjgl.opengl.GL11.*;
import static org.lwjgl.opengl.GL15.*;
import static org.lwjgl.opengl.GL20.*;
import static org.lwjgl.opengl.GL30.*;
import static org.lwjgl.system.MemoryUtil.NULL;

public class LwjglDemo {
    private static final String VERT_SRC =
        "#version 150 core\n" +
        "in vec2 aPos;\n" +
        "in vec3 aColor;\n" +
        "uniform float uAngle;\n" +
        "uniform float uAspect;\n" +
        "out vec3 vColor;\n" +
        "void main() {\n" +
        "    float c = cos(uAngle);\n" +
        "    float s = sin(uAngle);\n" +
        "    vec2 p = vec2(aPos.x * c - aPos.y * s, aPos.x * s + aPos.y * c);\n" +
        "    p.x /= uAspect;\n" +
        "    gl_Position = vec4(p, 0.0, 1.0);\n" +
        "    vColor = aColor;\n" +
        "}\n";

    private static final String FRAG_SRC =
        "#version 150 core\n" +
        "in vec3 vColor;\n" +
        "out vec4 FragColor;\n" +
        "void main() {\n" +
        "    FragColor = vec4(vColor, 1.0);\n" +
        "}\n";

    private static int compileShader(int type, String src) {
        int s = glCreateShader(type);
        glShaderSource(s, src);
        glCompileShader(s);
        if (glGetShaderi(s, GL_COMPILE_STATUS) == GL_FALSE) {
            throw new RuntimeException("Shader compile failed: " + glGetShaderInfoLog(s));
        }
        return s;
    }

    private static void checkOpenAL() {
        try {
            long dev = ALC10.alcOpenDevice((ByteBuffer) null);
            if (dev == NULL) {
                System.out.println("OPENAL_CHECK=FAIL (alcOpenDevice returned NULL)");
                return;
            }
            String name = ALC10.alcGetString(dev, ALC10.ALC_DEVICE_SPECIFIER);
            long ctx = ALC10.alcCreateContext(dev, (IntBuffer) null);
            boolean madeCurrent = ctx != NULL && ALC10.alcMakeContextCurrent(ctx);
            System.out.println("OPENAL_CHECK=OK device=\"" + name + "\" ctx=" + (ctx != NULL) + " current=" + madeCurrent);
            if (ctx != NULL) {
                ALC10.alcMakeContextCurrent(NULL);
                ALC10.alcDestroyContext(ctx);
            }
            ALC10.alcCloseDevice(dev);
        } catch (Throwable t) {
            System.out.println("OPENAL_CHECK=ERROR " + t);
        }
    }

    private static void dumpFramePPM(String path, int w, int h) {
        try {
            ByteBuffer buf = ByteBuffer.allocateDirect(w * h * 4);
            glPixelStorei(GL_PACK_ALIGNMENT, 1);
            glReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, buf);
            byte[] rgb = new byte[w * h * 3];
            for (int y = 0; y < h; y++) {
                int srcRow = (h - 1 - y) * w * 4;
                int dstRow = y * w * 3;
                for (int x = 0; x < w; x++) {
                    rgb[dstRow + x * 3] = buf.get(srcRow + x * 4);
                    rgb[dstRow + x * 3 + 1] = buf.get(srcRow + x * 4 + 1);
                    rgb[dstRow + x * 3 + 2] = buf.get(srcRow + x * 4 + 2);
                }
            }
            try (FileOutputStream fos = new FileOutputStream(path)) {
                fos.write(("P6\n" + w + " " + h + "\n255\n").getBytes("ASCII"));
                fos.write(rgb);
            }
            System.out.println("FRAME_DUMP=" + path + " size=" + w + "x" + h);
        } catch (Throwable t) {
            System.out.println("FRAME_DUMP_ERROR=" + t);
        }
    }

    public static void main(String[] args) {
        double durationSec = 10.0;
        String envDur = System.getenv("DEMO_SECONDS");
        if (envDur != null && !envDur.isEmpty()) {
            durationSec = Double.parseDouble(envDur);
        }

        System.out.println("DEMO_START lwjgl=" + Version.getVersion() + " java=" + System.getProperty("java.version"));
        GLFWErrorCallback.createPrint(System.err).set();

        if (!glfwInit()) {
            throw new IllegalStateException("Unable to initialize GLFW");
        }
        System.out.println("GLFW_VERSION=" + glfwGetVersionString());

        long monitor = glfwGetPrimaryMonitor();
        if (monitor != NULL) {
            GLFWVidMode mode = glfwGetVideoMode(monitor);
            String mname = glfwGetMonitorName(monitor);
            System.out.println("MONITOR name=\"" + mname + "\" mode=" +
                (mode != null ? (mode.width() + "x" + mode.height() + "@" + mode.refreshRate() + "Hz") : "null"));
        }

        // Verify HIToolbox TIS / UCKeyTranslate path via glfwGetKeyName
        String keyW = glfwGetKeyName(GLFW_KEY_W, 0);
        String keyA = glfwGetKeyName(GLFW_KEY_A, 0);
        System.out.println("KEY_NAMES W=\"" + keyW + "\" A=\"" + keyA + "\"");

        glfwDefaultWindowHints();
        glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
        glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 2);
        glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
        glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GLFW_TRUE);
        glfwWindowHint(GLFW_VISIBLE, GLFW_TRUE);
        glfwWindowHint(GLFW_RESIZABLE, GLFW_TRUE);

        long window = glfwCreateWindow(854, 480, "SiliconForest LWJGL 3.3.3 GL 3.2 Core Demo", NULL, NULL);
        if (window == NULL) {
            glfwTerminate();
            throw new RuntimeException("Failed to create GLFW window");
        }

        glfwMakeContextCurrent(window);
        glfwSwapInterval(1);
        GL.createCapabilities();

        System.out.println("GL_VERSION=" + glGetString(GL_VERSION));
        System.out.println("GL_RENDERER=" + glGetString(GL_RENDERER));
        System.out.println("GL_VENDOR=" + glGetString(GL_VENDOR));
        System.out.println("GL_SHADING_LANGUAGE_VERSION=" + glGetString(GL_SHADING_LANGUAGE_VERSION));

        try (MemoryStack stack = MemoryStack.stackPush()) {
            IntBuffer ww = stack.mallocInt(1), wh = stack.mallocInt(1);
            IntBuffer fw = stack.mallocInt(1), fh = stack.mallocInt(1);
            FloatBuffer sx = stack.mallocFloat(1), sy = stack.mallocFloat(1);
            glfwGetWindowSize(window, ww, wh);
            glfwGetFramebufferSize(window, fw, fh);
            glfwGetWindowContentScale(window, sx, sy);
            System.out.printf("WINDOW_GEOM logical=%dx%d framebuffer=%dx%d scale=%.2fx%.2f%n",
                ww.get(0), wh.get(0), fw.get(0), fh.get(0), sx.get(0), sy.get(0));
        }

        checkOpenAL();

        final int[] keyEvents = {0};
        final int[] cursorEvents = {0};
        final double[] lastCursor = {Double.NaN, Double.NaN};

        glfwSetKeyCallback(window, (win, key, scancode, action, mods) -> {
            keyEvents[0]++;
            String name = glfwGetKeyName(key, scancode);
            System.out.printf("KEY_EVENT n=%d key=%d scancode=%d name=%s action=%d mods=%d%n",
                keyEvents[0], key, scancode, name, action, mods);
            if (key == GLFW_KEY_ESCAPE && action == GLFW_PRESS) {
                glfwSetWindowShouldClose(win, true);
            }
        });

        glfwSetCursorPosCallback(window, (win, xpos, ypos) -> {
            cursorEvents[0]++;
            double dx = Double.isNaN(lastCursor[0]) ? 0.0 : xpos - lastCursor[0];
            double dy = Double.isNaN(lastCursor[1]) ? 0.0 : ypos - lastCursor[1];
            lastCursor[0] = xpos;
            lastCursor[1] = ypos;
            int mode = glfwGetInputMode(win, GLFW_CURSOR);
            if (cursorEvents[0] <= 20 || cursorEvents[0] % 30 == 0) {
                System.out.printf("CURSOR_EVENT n=%d mode=%s pos=(%.2f,%.2f) delta=(%.2f,%.2f)%n",
                    cursorEvents[0],
                    mode == GLFW_CURSOR_DISABLED ? "DISABLED" : "NORMAL",
                    xpos, ypos, dx, dy);
            }
        });

        int vs = compileShader(GL_VERTEX_SHADER, VERT_SRC);
        int fs = compileShader(GL_FRAGMENT_SHADER, FRAG_SRC);
        int prog = glCreateProgram();
        glAttachShader(prog, vs);
        glAttachShader(prog, fs);
        glBindAttribLocation(prog, 0, "aPos");
        glBindAttribLocation(prog, 1, "aColor");
        glLinkProgram(prog);
        if (glGetProgrami(prog, GL_LINK_STATUS) == GL_FALSE) {
            throw new RuntimeException("Program link failed: " + glGetProgramInfoLog(prog));
        }
        glDeleteShader(vs);
        glDeleteShader(fs);

        int uAngle = glGetUniformLocation(prog, "uAngle");
        int uAspect = glGetUniformLocation(prog, "uAspect");

        float[] verts = {
             0.0f,  0.75f,  1.0f, 0.2f, 0.2f,
            -0.65f, -0.55f, 0.2f, 1.0f, 0.3f,
             0.65f, -0.55f, 0.2f, 0.5f, 1.0f
        };

        int vao = glGenVertexArrays();
        int vbo = glGenBuffers();
        glBindVertexArray(vao);
        glBindBuffer(GL_ARRAY_BUFFER, vbo);
        glBufferData(GL_ARRAY_BUFFER, verts, GL_STATIC_DRAW);
        glVertexAttribPointer(0, 2, GL_FLOAT, false, 5 * Float.BYTES, 0);
        glEnableVertexAttribArray(0);
        glVertexAttribPointer(1, 3, GL_FLOAT, false, 5 * Float.BYTES, 2L * Float.BYTES);
        glEnableVertexAttribArray(1);
        glBindVertexArray(0);

        double t0 = glfwGetTime();
        double lastReport = t0;
        long frames = 0;
        long reportFrames = 0;
        boolean disabledTested = false;
        boolean restoredTested = false;

        System.out.flush();

        while (!glfwWindowShouldClose(window)) {
            double now = glfwGetTime();
            double elapsed = now - t0;
            if (elapsed >= durationSec) {
                break;
            }

            if (!disabledTested && elapsed >= 3.5) {
                disabledTested = true;
                int focused = glfwGetWindowAttrib(window, GLFW_FOCUSED);
                System.out.println("CURSOR_MODE_SWITCH -> GLFW_CURSOR_DISABLED at t=" + String.format("%.2f", elapsed) + " focused=" + focused);
                glfwSetInputMode(window, GLFW_CURSOR, GLFW_CURSOR_DISABLED);
                glfwSetCursorPos(window, 427.0, 240.0);
                System.out.println("CURSOR_MODE_NOW=" + (glfwGetInputMode(window, GLFW_CURSOR) == GLFW_CURSOR_DISABLED ? "DISABLED" : "OTHER"));
                System.out.flush();
            }
            if (!restoredTested && elapsed >= 7.5) {
                restoredTested = true;
                System.out.println("CURSOR_MODE_SWITCH -> GLFW_CURSOR_NORMAL at t=" + String.format("%.2f", elapsed));
                glfwSetInputMode(window, GLFW_CURSOR, GLFW_CURSOR_NORMAL);
                System.out.println("CURSOR_MODE_NOW=" + (glfwGetInputMode(window, GLFW_CURSOR) == GLFW_CURSOR_NORMAL ? "NORMAL" : "OTHER"));
                System.out.flush();
            }

            int fbW, fbH;
            try (MemoryStack stack = MemoryStack.stackPush()) {
                IntBuffer fw = stack.mallocInt(1), fh = stack.mallocInt(1);
                glfwGetFramebufferSize(window, fw, fh);
                fbW = Math.max(1, fw.get(0));
                fbH = Math.max(1, fh.get(0));
            }
            glViewport(0, 0, fbW, fbH);
            glClearColor(0.08f, 0.11f, 0.22f, 1.0f);
            glClear(GL_COLOR_BUFFER_BIT);

            glUseProgram(prog);
            glUniform1f(uAngle, (float) (elapsed * 1.4));
            glUniform1f(uAspect, (float) fbW / (float) fbH);
            glBindVertexArray(vao);
            glDrawArrays(GL_TRIANGLES, 0, 3);
            glBindVertexArray(0);

            String dumpDir = System.getenv("DEMO_DUMP_DIR");
            if (dumpDir != null && !dumpDir.isEmpty()) {
                if (frames == 90) dumpFramePPM(dumpDir + "/gpu-frame-090.ppm", fbW, fbH);
                else if (frames == 240) dumpFramePPM(dumpDir + "/gpu-frame-240.ppm", fbW, fbH);
            }

            glfwSwapBuffers(window);
            glfwPollEvents();

            frames++;
            reportFrames++;
            if (now - lastReport >= 2.0) {
                double fps = reportFrames / (now - lastReport);
                System.out.printf("FPS_SAMPLE t=%.2fs frames=%d fps=%.1f cursor_events=%d key_events=%d glErr=0x%x%n",
                    elapsed, frames, fps, cursorEvents[0], keyEvents[0], glGetError());
                System.out.flush();
                lastReport = now;
                reportFrames = 0;
            }
        }

        double totalTime = Math.max(0.001, glfwGetTime() - t0);
        System.out.printf("DEMO_DONE frames=%d elapsed=%.2fs avg_fps=%.1f key_events=%d cursor_events=%d glErr=0x%x%n",
            frames, totalTime, frames / totalTime, keyEvents[0], cursorEvents[0], glGetError());
        System.out.flush();

        glDeleteVertexArrays(vao);
        glDeleteBuffers(vbo);
        glDeleteProgram(prog);
        glfwDestroyWindow(window);
        glfwTerminate();
    }
}
