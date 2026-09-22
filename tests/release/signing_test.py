import hashlib, importlib.util, json, os, pathlib, secrets, shutil, subprocess, tempfile, unittest, zipfile
ROOT=pathlib.Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('signing_setup', ROOT/'scripts/provision-android-signing.py')
setup=importlib.util.module_from_spec(spec);spec.loader.exec_module(setup)

class SigningTest(unittest.TestCase):
    def test_refuses_repository_or_existing_destination(self):
        with self.assertRaises(ValueError): setup.provision(ROOT/'.tmp/forbidden-key')
        with tempfile.TemporaryDirectory() as directory:
            marker=pathlib.Path(directory)/'existing';marker.write_text('keep')
            with self.assertRaises(FileExistsError): setup.provision(directory)
            self.assertEqual(marker.read_text(),'keep')

@unittest.skipUnless(all(shutil.which(x) for x in ['keytool','jarsigner','java','openssl']), 'JDK and OpenSSL required')
class BundleSignatureTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp=tempfile.TemporaryDirectory();cls.dir=pathlib.Path(cls.temp.name)
        cls.key=cls.dir/'fixture.jks';cls.env={**os.environ,'SIGN_TEST_PASSWORD':secrets.token_urlsafe(32)}
        def run(args,**kwargs): return subprocess.run(args,env=cls.env,check=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE,**kwargs)
        cls.run_command=staticmethod(run)
        run(['keytool','-genkeypair','-noprompt','-storetype','JKS','-keystore',str(cls.key),'-storepass:env','SIGN_TEST_PASSWORD','-keypass:env','SIGN_TEST_PASSWORD','-alias','fixture','-keyalg','RSA','-keysize','3072','-sigalg','SHA256withRSA','-validity','5000','-dname','CN=BioBalance synthetic test'])
        cert=run(['keytool','-exportcert','-keystore',str(cls.key),'-storepass:env','SIGN_TEST_PASSWORD','-alias','fixture']).stdout
        cls.sha=hashlib.sha256(cert).hexdigest();cls.bundle=cls.dir/'bundle.aab'
        with zipfile.ZipFile(cls.bundle,'w') as z:z.writestr('base/manifest/AndroidManifest.xml','synthetic')
        run(['jarsigner','-keystore',str(cls.key),'-storepass:env','SIGN_TEST_PASSWORD','-keypass:env','SIGN_TEST_PASSWORD','-sigalg','SHA256withRSA','-digestalg','SHA-256',str(cls.bundle),'fixture'])
    @classmethod
    def tearDownClass(cls):cls.temp.cleanup()
    def verify(self,file,sha):
        return subprocess.run(['java',str(ROOT/'scripts/VerifyAndroidBundle.java'),str(file),sha],stdout=subprocess.PIPE,stderr=subprocess.PIPE).returncode
    def test_expected_signer_and_wrong_signer(self):
        self.assertEqual(self.verify(self.bundle,self.sha),0)
        self.assertNotEqual(self.verify(self.bundle,'0'*64),0)
    def test_rejects_unsigned_injected_entry(self):
        injected=self.dir/'injected.aab';shutil.copy2(self.bundle,injected)
        with zipfile.ZipFile(injected,'a') as z:z.writestr('base/assets/injected','malicious')
        self.assertNotEqual(self.verify(injected,self.sha),0)
    def test_rejects_changed_signed_content(self):
        tampered=self.dir/'tampered.aab'
        with zipfile.ZipFile(self.bundle) as source, zipfile.ZipFile(tampered,'w') as target:
            for entry in source.infolist():
                target.writestr(entry,b'tampered' if entry.filename=='base/manifest/AndroidManifest.xml' else source.read(entry))
        self.assertNotEqual(self.verify(tampered,self.sha),0)
    def test_certificate_identity_is_checked_before_build(self):
        env={**self.env,'BIOBALANCE_KEYSTORE':str(self.key),'BIOBALANCE_KEYSTORE_PASSWORD':self.env['SIGN_TEST_PASSWORD'],'BIOBALANCE_KEY_ALIAS':'fixture','BIOBALANCE_CERT_SHA256':self.sha}
        policy=self.dir/'policy.json';policy.write_text(json.dumps({'appCertificateSha256':self.sha}))
        args=['python3',str(ROOT/'scripts/verify-android-signer.py'),'key','BIOBALANCE_',str(policy)]
        self.assertEqual(subprocess.run(args,env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE).returncode,0)
        env['BIOBALANCE_CERT_SHA256']='0'*64
        self.assertNotEqual(subprocess.run(args,env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE).returncode,0)
