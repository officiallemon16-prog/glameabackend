import subprocess, os
os.chdir(r'C:\Users\hp\Desktop\GLAMEA\frontend')
env = os.environ.copy()
env['API_BASE_URL'] = 'http://localhost:8080/api/v1'
p = subprocess.Popen(
    [r'C:\src\flutter\bin\flutter.bat', 'run', '-d', 'web-server',
     '--web-port=3001', '--web-hostname=0.0.0.0',
     '--dart-define=API_BASE_URL=http://localhost:8080/api/v1'],
    env=env,
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
    text=True,
    creationflags=0x08000000
)
with open(r'C:\Users\hp\Desktop\GLAMEA\flutter_run.log', 'w') as f:
    for line in p.stdout:
        f.write(line)
        f.flush()
        print(line, end='')
p.wait()
