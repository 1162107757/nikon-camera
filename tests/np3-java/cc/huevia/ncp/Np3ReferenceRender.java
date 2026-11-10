package cc.huevia.ncp;

import java.awt.image.BufferedImage;
import java.io.File;
import java.nio.file.Files;
import javax.imageio.ImageIO;

/** Research utility: a Nikon-exported neutral RGB image, not the camera JPEG. */
public final class Np3ReferenceRender {
    public static void main(String[] args)throws Exception {
        Np3PreviewProfile profile=Np3PreviewProfile.fromNp3(Files.readAllBytes(new File(args[0]).toPath()));
        BufferedImage input=ImageIO.read(new File(args[1]));
        BufferedImage output=new BufferedImage(input.getWidth(),input.getHeight(),BufferedImage.TYPE_INT_RGB);
        for(int y=0;y<input.getHeight();y++)for(int x=0;x<input.getWidth();x++)output.setRGB(x,y,profile.applyArgb(input.getRGB(x,y)));
        ImageIO.write(output,"PNG",new File(args[2]));
        System.out.println(profile.registrationName()+" / "+profile.modelVersion());
    }
}
