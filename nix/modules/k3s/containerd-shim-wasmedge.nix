{ pkgs, lib, stdenv }:

let
  inherit (stdenv.hostPlatform) system;
  throwSystem = "Unsupported system: ${system}";

  plat = {
    x86_64-linux = "x86_64";
    aarch64-linux = "aarch64";
  }.${system} or throwSystem;

  sha256 = {
    x86_64-linux = "0vxkqqm6pfw5php0pj5j06rgsa748q27f8l97rs3kbc5ykmi5k73";
    aarch64-linux = "1l0jhpqdnxxnwqr6qixc8ai4zymcpxc4a3ca2lwyc7akbpw2hj99";
  }.${system} or throwSystem;
in
pkgs.stdenv.mkDerivation rec {
	pname = "containerd-shim-wasmedge";
	version = "0.4.0";

	src = builtins.fetchurl {
		url = "https://github.com/containerd/runwasi/releases/download/containerd-shim-wasmedge%2F${version}/containerd-shim-wasmedge-${plat}.tar.gz";
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
		platforms = ["x86_64-linux" "aarch64-linux"];
		license = licenses.asl20;
	};
}