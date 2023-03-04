test:
  nix flake check
  @notify-send "Nixus" "Finished tests"
