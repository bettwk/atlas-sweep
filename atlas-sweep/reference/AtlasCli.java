// Atlas'ın özgün Java kodunu (github.com/savastakan/atlas) bir .fsm dosyası üzerinde çalıştırıp
// test dizisini yazdırır. Main.java dosya yolunu sabit yazdığı için bu küçük çalıştırıcı yazıldı;
// Atlas'ın kendisine dokunulmaz.
//   javac -d /tmp/jatlas <atlas-deposu>/*.java reference/AtlasCli.java
//   java -Xss64m -cp /tmp/jatlas AtlasCli dosya.fsm
public class AtlasCli {
    public static void main(String[] args) throws Exception {
        Graph graph = new Util().toGraph(args[0]);
        System.out.println(new Atlas().run(graph));
    }
}
