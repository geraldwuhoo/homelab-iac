# Builder for runwasi containerd shims. k3s discovers these on the service PATH
# and generates the containerd runtime config itself, so nothing needs to be
# written into /var/lib/rancher.
{
  lib,
  stdenvNoCC,
  fetchurl,
}:

{
  runtime,
  version,
  hashes,
}:

let
  inherit (stdenvNoCC.hostPlatform) system;
  throwSystem = throw "Unsupported system: ${system}";

  plat =
    {
      x86_64-linux = "x86_64";
      aarch64-linux = "aarch64";
    }
    .${system} or throwSystem;

  binary = "containerd-shim-${runtime}-v1";
in
stdenvNoCC.mkDerivation {
  pname = "containerd-shim-${runtime}";
  inherit version;

  src = fetchurl {
    url = "https://github.com/containerd/runwasi/releases/download/containerd-shim-${runtime}%2Fv${version}/containerd-shim-${runtime}-${plat}-linux-musl.tar.gz";
    hash = hashes.${system} or throwSystem;
  };

  # The tarball is flat: the binary sits alongside its sigstore .pem/.sig.
  sourceRoot = ".";

  # Prebuilt static musl binary, keep it byte-identical to the signed release.
  dontStrip = true;
  dontPatchELF = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 ${binary} $out/bin/${binary}
    runHook postInstall
  '';

  meta = with lib; {
    homepage = "https://github.com/containerd/runwasi";
    description = "containerd shim for running ${runtime} WebAssembly workloads";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    license = licenses.asl20;
    mainProgram = binary;
  };
}
