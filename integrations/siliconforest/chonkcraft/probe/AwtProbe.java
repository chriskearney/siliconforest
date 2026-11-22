// SPDX-License-Identifier: MIT
// A small AWT window for bringing the JetBrains Runtime up on SiliconForest:
// opens a 640x400 frame, paints colour bars and text, prints what Java
// thinks the window and screen are, and writes the painted frame to a PNG
// (argument 1) so the Java2D result can be compared with the desk capture.
import java.awt.*;
import java.awt.image.BufferedImage;
import java.io.File;
import javax.imageio.ImageIO;
import javax.swing.*;

public final class AwtProbe {
    static final class Bars extends JComponent {
        int paints;
        @Override protected void paintComponent(Graphics g0) {
            paints++;
            Graphics2D g = (Graphics2D) g0;
            Color[] c = { Color.RED, Color.ORANGE, Color.YELLOW, Color.GREEN, Color.CYAN, Color.BLUE, Color.MAGENTA };
            int w = getWidth(), h = getHeight();
            for (int i = 0; i < c.length; i++) {
                g.setColor(c[i]);
                g.fillRect(i * w / c.length, 0, w / c.length + 1, h * 2 / 3);
            }
            g.setColor(Color.BLACK);
            g.fillRect(0, h * 2 / 3, w, h);
            g.setColor(Color.WHITE);
            for (int i = 0; i <= paints % 20; i++)   // a paint counter that needs no font
                g.fillRect(20 + i * 14, h * 2 / 3 + 100, 10, 10);
            try {   // text needs a system font; a missing one must not stop the bars
                g.setFont(new Font(Font.SANS_SERIF, Font.BOLD, 28));
                g.drawString("JBR " + System.getProperty("java.runtime.version") + " on SiliconForest", 20, h * 2 / 3 + 40);
                g.drawString("paint #" + paints + "  " + w + "x" + h, 20, h * 2 / 3 + 80);
            } catch (RuntimeException e) {
                if (paints == 1) System.out.println("text failed: " + e);
            }
        }
    }

    public static void main(String[] args) throws Exception {
        String out = args.length > 0 ? args[0] : null;
        GraphicsEnvironment ge = GraphicsEnvironment.getLocalGraphicsEnvironment();
        for (GraphicsDevice d : ge.getScreenDevices()) {
            System.out.println("device " + d.getIDstring() + " bounds=" + d.getDefaultConfiguration().getBounds()
                    + " mode=" + d.getDisplayMode().getWidth() + "x" + d.getDisplayMode().getHeight());
        }
        Bars bars = new Bars();
        JFrame[] holder = new JFrame[1];
        SwingUtilities.invokeAndWait(() -> {
            JFrame f = new JFrame("AWT probe");
            f.setDefaultCloseOperation(JFrame.EXIT_ON_CLOSE);
            bars.setPreferredSize(new Dimension(640, 400));
            f.getContentPane().add(bars);
            f.pack();
            f.setLocation(200, 150);
            f.setVisible(true);
            holder[0] = f;
        });
        for (int i = 0; i < 6; i++) {
            Thread.sleep(1000);
            SwingUtilities.invokeAndWait(() -> {
                JFrame f = holder[0];
                System.out.println("frame bounds=" + f.getBounds() + " insets=" + f.getInsets()
                        + " content=" + bars.getSize() + " paints=" + bars.paints + " showing=" + f.isShowing());
                bars.repaint();
            });
        }
        if (out != null) {
            BufferedImage img = new BufferedImage(640, 400, BufferedImage.TYPE_INT_RGB);
            Graphics2D g = img.createGraphics();
            bars.setSize(640, 400);
            bars.paintComponent(g);
            g.dispose();
            ImageIO.write(img, "png", new File(out));
            System.out.println("wrote " + out);
        }
    }
}
