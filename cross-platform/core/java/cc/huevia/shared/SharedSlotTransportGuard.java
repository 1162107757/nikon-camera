package cc.huevia.shared;

import cc.huevia.picturecontrol.PictureControlWriteValidation;
import java.io.IOException;

/** One native owner, one PTP session and at most one destructive attempt, shared by both USB hosts. */
public final class SharedSlotTransportGuard {
    private boolean opened,closed,attempted;
    private int deletion=-1;
    private long last;
    public void read(int operation,long transaction,long[] p)throws IOException {
        boolean valid=p!=null&&(operation==0x1001&&p.length==0
                ||operation==0x90cf&&p.length==1&&p[0]==1
                ||operation==0x90cc&&p.length==2&&p[0]>=201&&p[0]<=209&&p[1]==0
                ||operation==0x1015&&deletion>=201&&p.length==1&&(p[0]==0xd200||p[0]==0xd237));
        if(!valid)throw new IOException("槽位通道拒绝未授权的读取。");
        transaction(transaction,operation==0x1001&&!opened);
    }
    public void command(int operation,long transaction,long[] p)throws IOException {
        if(p==null)throw new IOException("PTP 参数不能为空。");
        if(operation==0x1002&&p.length==1&&p[0]==1&&!opened&&!closed&&transaction==0){opened=true;return;}
        if(operation==0x1003&&p.length==0&&opened&&!closed){transaction(transaction,false);closed=true;opened=false;return;}
        if(operation==0x90ce&&p.length==1&&p[0]==deletion&&deletion>=201&&!attempted){transaction(transaction,false);attempted=true;return;}
        throw new IOException("槽位通道拒绝未授权的命令。");
    }
    public void send(int operation,long transaction,byte[] bytes,long[] p)throws IOException {
        if(operation!=0x90cd||p==null||p.length!=2||p[0]<201||p[0]>209||p[1]!=0||deletion!=-1||attempted)throw new IOException("仅允许一次已确认的 C1–C9 预设写入。");
        PictureControlWriteValidation.validateConvertedData(bytes);transaction(transaction,false);attempted=true;
    }
    public void authorizeDeletion(int target)throws IOException {
        if(!opened||closed||attempted||deletion!=-1||target<201||target>209)throw new IOException("此连接不能再次授权删除。");deletion=target;
    }
    private void transaction(long transaction,boolean beforeOpen)throws IOException {
        if(closed||transaction<0||transaction>0xffffffffL||beforeOpen&&transaction!=0||!beforeOpen&&(!opened||transaction<=last))throw new IOException("PTP 会话或事务序列无效。");
        if(!beforeOpen)last=transaction;
    }
}
