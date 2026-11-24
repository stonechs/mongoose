# Mongoose HTTP Server

Windows IPv4 static web server based on Mongoose. Current version: **V1.0**.

## Build

Run from the project root:

```powershell
.\Script\build-clang.ps1 -Architecture x86
.\Script\build-crinkler.ps1
.\Script\build-clang.ps1 -Architecture x64
```

These produce the three official builds in `dist/`: Clang x86, Crinkler x86,
and Clang x64. Build scripts copy the sample `index.html` beside the EXEs.

## Run

Start an EXE and choose **Start browser** from its tray menu. The server uses
the EXE's directory as its site root and listens on `http://127.0.0.1:8000/`.
Keep `index.html` beside the EXE. Settings are stored in `mongoose.conf`.

The server binds to all IPv4 interfaces and has no TLS or authentication.

See [docs/project_status.md](docs/project_status.md) for verified build details
and [docs/mongoose_design_analysis_zh.md](docs/mongoose_design_analysis_zh.md)
for the Mongoose feature overview.
