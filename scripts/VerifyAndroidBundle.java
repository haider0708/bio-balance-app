import java.io.InputStream;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.util.HexFormat;
import java.util.jar.JarFile;

/** JarFile verifies every entry's digest and signature as it is read. */
class VerifyAndroidBundle {
  public static void main(String[] args) throws Exception {
    String expected = args[1].replace(":", "").toLowerCase();
    if (!expected.matches("[a-f0-9]{64}")) throw new SecurityException("Invalid certificate fingerprint");
    int count = 0;
    try (JarFile jar = new JarFile(Path.of(args[0]).toFile(), true)) {
      var entries = jar.entries();
      while (entries.hasMoreElements()) {
        var entry = entries.nextElement();
        if (entry.isDirectory()) continue;
        try (InputStream input = jar.getInputStream(entry)) { input.transferTo(java.io.OutputStream.nullOutputStream()); }
        String name = entry.getName();
        if (name.matches("(?i)META-INF/(MANIFEST\\.MF|[^/]+\\.(SF|RSA|DSA|EC))")) continue;
        var signers = entry.getCodeSigners();
        if (signers == null || signers.length != 1) throw new SecurityException("Unsigned or ambiguous bundle entry");
        var cert = signers[0].getSignerCertPath().getCertificates().get(0);
        String digest = HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(cert.getEncoded()));
        if (!digest.equals(expected)) throw new SecurityException("Wrong upload certificate");
        count++;
      }
    }
    if (count == 0) throw new SecurityException("Empty signed bundle");
    System.out.println("Verified " + count + " signed entries; upload certificate SHA-256: " + expected);
  }
}
