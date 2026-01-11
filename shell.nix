{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = [
    pkgs.tilt
    pkgs.go-task
    pkgs.git
    pkgs.docker-compose
  ];

  shellHook = ''
    echo "Welcome to the URFD development environment!"
    echo "Run 'task init' to get started."
  '';
}
