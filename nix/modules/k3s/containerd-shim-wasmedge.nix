{
  pkgs,
  lib,
  stdenv,
}:

let
  inherit (stdenv.hostPlatform) system;
  throwSystem = "Unsupported system: ${system}";

  plat =
    {
      x86_64-linux = "x86_64";
      aarch64-linux = "aarch64";
    }
    .${system} or throwSystem;

  sha256 =
    {
      x86_64-linux = "1qvx6h44b68arbxc0x3kyn5pmccwddvzy5gg68g3xsbvr0j8sf44";
      aarch64-linux = "0i7r5n4dprj2w2lr4f3mcwjr87ij4bnfkiav5ixysw8maf0vfsfr";
    }
    .${system} or throwSystem;
in
pkgs.stdenv.mkDerivation rec {
  pname = "containerd-shim-wasmedge";
  version = "0.5.0";

  src = builtins.fetchurl {
    url = "https://github.com/containerd/runwasi/releases/download/containerd-shim-wasmedge%2Fv${version}/containerd-shim-wasmedge-${plat}-linux-musl.tar.gz";
    inherit sha256;
  };

  doCheck = false;

  dontUnpack = true;

  installPhase = ''
    echo $src $out
    mkdir -p $out
    tar -xzf $src -C $out
  '';

  meta = with lib; {
    homepage = "https://github.com/containerd/runwasi";
    description = "wasm";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    license = licenses.asl20;
  };
}
