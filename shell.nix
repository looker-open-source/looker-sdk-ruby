let
  nixpkgs = import (builtins.fetchTarball {
    name = "nixpkgs-21.05";
    url =
      "https://github.com/nixos/nixpkgs/archive/f7574a5c8fefd86b50def1827eadb9b8cb266ffd.tar.gz";
    sha256 = "0pksag38bjdqwvmcxgyc5a31hfz1z201za21v3hb7mqd9b99lnr3";
  }) { };
in
with nixpkgs;
with stdenv;
with lib;
let ruby' = ruby_2_6.withPackages(ps: with ps; [bundler rake]);
in
mkShell {
  name = "cucu-shell";
  buildInputs = [ ruby' lzma zlib libxml2 ];

  # Looker expects this as the default encoding otherwise does not start
  LANG = "en_US.UTF-8";

  # https://nixos.org/nixpkgs/manual/#locales
  LOCALE_ARCHIVE =
      optionalString isLinux "${glibcLocales}/lib/locale/locale-archive";

  shellHook = ''
      # FIXME: SSH or tooling that requires libnss-cache (https://github.com/google/libnss-cache)
      # seems to fail since the library is not present. When I have a better understanding of Nix
      # let's fix this.
      # https://github.com/NixOS/nixpkgs/issues/64665#issuecomment-511411309
      [[ ! -f /lib/x86_64-linux-gnu/libnss_cache.so.2 ]] || export LD_PRELOAD=/lib/x86_64-linux-gnu/libnss_cache.so.2:$LD_PRELOAD

      export GEM_USER_DIR=$(pwd)/.gem
      export GEM_DEFAULT_DIR=$(${ruby'}/bin/ruby -e 'puts Gem.default_dir')
      export GEM_PATH=$GEM_DEFAULT_DIR:$GEM_PATH
      export GEM_HOME=$GEM_USER_DIR
      export PATH=$GEM_HOME/bin:$PATH
     '';
}
