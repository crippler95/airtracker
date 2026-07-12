.PHONY: build bundle run debug clean reset-tcc listen-4242 listen-json

APP := build/AirTracker.app
BUNDLE_ID := com.szilard.airtracker

build:
	swift build -c release

bundle:
	./scripts/bundle.sh release

# Build, bundle, sign, and launch via LaunchServices so the Motion (TCC) prompt appears.
run: bundle
	open "$(APP)"

# Faster dev loop with a debug build.
debug:
	./scripts/bundle.sh debug
	open "$(APP)"

clean:
	rm -rf build .build

# Ad-hoc signatures change their CDHash every build, so TCC may re-prompt or silently
# deny after a rebuild. Reset the Motion grant if the app stops receiving data.
reset-tcc:
	tccutil reset Motion $(BUNDLE_ID) || true

# Verify the opentrack UDP stream: prints x,y,z,yaw,pitch,roll from each 48-byte packet.
listen-4242:
	python3 -c "import socket,struct; s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); s.bind(('0.0.0.0',4242)); print('listening on 4242...'); [print(['%.2f'%v for v in struct.unpack('<6d', s.recv(48))]) for _ in iter(int,1)]"

# Verify the JSON UDP stream.
listen-json:
	python3 -c "import socket; s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); s.bind(('0.0.0.0',4243)); print('listening on 4243...'); [print(s.recv(2048).decode()) for _ in iter(int,1)]"
