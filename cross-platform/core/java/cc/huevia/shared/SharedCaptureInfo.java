package cc.huevia.shared;

import cc.huevia.ncp.PhotoBorder;
import cc.huevia.library.SharedJson;
import java.io.IOException;
import java.util.*;

/** Original Android capture-label rules, fed by the platform's read-only EXIF reader. */
public final class SharedCaptureInfo {
    public final String brand,model;
    private final String[] fields;
    public SharedCaptureInfo(String json)throws IOException{
        Map<String,Object> p=SharedJson.object(json);String make=value(p,"Make");model=value(p,"Model");brand=brandKey(make.isEmpty()?model:make);
        String focal=number(value(p,"FocalLength")),aperture=number(value(p,"FNumber"));double seconds=decimal(value(p,"ExposureTime"));
        String shutter=seconds>0?(seconds<1?"1/"+Math.round(1/seconds):number(Double.toString(seconds)))+"s":"";
        String iso=value(p,"PhotographicSensitivity");if(iso.isEmpty())iso=value(p,"ISOSpeedRatings");if(!iso.matches("[1-9][0-9]{0,6}"))iso="";
        String date=value(p,"DateTimeOriginal");if(date.isEmpty())date=value(p,"DateTimeDigitized");if(!date.matches("[0-9]{4}:[0-9]{2}:[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}"))date="";else date=date.substring(0,10).replace(':','-')+date.substring(10);
        fields=new String[]{focal.isEmpty()?"":focal+"mm",aperture.isEmpty()?"":"F"+aperture,shutter,iso.isEmpty()?"":"ISO"+iso,date};
    }
    private static String value(Map<String,Object> p,String key)throws IOException{return SharedRuntime.text(p,key,1024).trim().replaceAll("[\\p{Cntrl}]"," ");}
    private static double decimal(String s){try{String[] p=s.split("/");double v=p.length==2?Double.parseDouble(p[0])/Double.parseDouble(p[1]):Double.parseDouble(s);return Double.isFinite(v)&&v>0&&v<1e9?v:0;}catch(RuntimeException invalid){return 0;}}
    private static String number(String s){double v=decimal(s);if(v==0)return "";return String.format(Locale.US,"%.2f",v).replaceAll("0+$","").replaceAll("\\.$","");}
    public static String brandKey(String name){String n=name.toUpperCase(Locale.ROOT);if(n.contains("NIKON"))return "NIKON";if(n.contains("FUJI"))return "FUJIFILM";if(n.contains("SONY"))return "SONY";if(n.contains("CANON"))return "CANON";return name.trim();}
    public String brand(PhotoBorder b){return b.automatic?brand:b.brand;}
    public String model(PhotoBorder b){return b.automatic?model:b.model;}
    public String field(PhotoBorder b,int index){return b.field(index).isEmpty()?fields[index]:b.field(index);}
    public String parameters(PhotoBorder b){StringJoiner s=new StringJoiner("  ");for(int i=0;i<4;i++)if(b.shows(i+1)&&!field(b,i).isEmpty())s.add(field(b,i));return s.toString();}
    public String company(PhotoBorder b){String s=brand(b);return s.equals("NIKON")?"NIKON CORPORATION":s;}
}
