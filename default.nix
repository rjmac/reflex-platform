{ nixpkgsFunc ? import ./nixpkgs
, system ? builtins.currentSystem
, config ? {}
, enableLibraryProfiling ? false
, enableExposeAllUnfoldings ? true
, enableTraceReflexEvents ? false
, useReflexOptimizer ? false
, useTextJSString ? true
, iosSdkVersion ? "10.2"
}:
let all-cabal-hashes = fetchFromGitHub {
      owner = "commercialhaskell";
      repo = "all-cabal-hashes";
      rev = "adb039bba3bb46941c3ee08bdd68f25bf2aa5c60";
      sha256 = "0mjkrbifag39gm153v5wn555jq7ckwn8s3f1wwsdw67wmql4gcn7";
    };
    nixpkgs = nixpkgsFunc ({
      inherit system;
      config = {
        allowUnfree = true;
        allowBroken = true; # GHCJS is marked broken in 011c149ed5e5a336c3039f0b9d4303020cff1d86
        permittedInsecurePackages = [
          "webkitgtk-2.4.11"
        ];
        packageOverrides = pkgs: {
          webkitgtk = pkgs.webkitgtk216x;
          # cabal2nix's tests crash on 32-bit linux; see https://github.com/NixOS/cabal2nix/issues/272
          ${if system == "i686-linux" then "cabal2nix" else null} = pkgs.haskell.lib.dontCheck pkgs.cabal2nix;
          inherit all-cabal-hashes;
        };
      } // config;
    });
    inherit (nixpkgs) fetchurl fetchgit fetchFromGitHub;
    nixpkgsCross = {
      android = nixpkgs.lib.mapAttrs (_: args: nixpkgsFunc args) rec {
        arm64 = {
          inherit system;
          crossSystem = {
            config = "aarch64-unknown-linux-android";
            arch = "arm64";
            libc = "bionic";
            withTLS = true;
            openssl.system = "linux-generic64";
            platform = nixpkgs.pkgs.platforms.aarch64-multiplatform;
          };
          config.allowUnfree = true;
          config.packageOverrides = pkgs: {
            inherit all-cabal-hashes;
          };
        };
        arm64Impure = arm64 // {
          inherit system;
          crossSystem = arm64.crossSystem // { useAndroidPrebuilt = true; };
        };
        armv7a = {
          inherit system;
          crossSystem = {
            config = "arm-unknown-linux-androideabi";
            arch = "armv7";
            libc = "bionic";
            withTLS = true;
            openssl.system = "linux-generic32";
            platform = nixpkgs.pkgs.platforms.armv7l-hf-multiplatform;
          };
          config.allowUnfree = true;
          config.packageOverrides = pkgs: {
            inherit all-cabal-hashes;
          };
        };
        armv7aImpure = armv7a // {
          crossSystem = armv7a.crossSystem // { useAndroidPrebuilt = true; };
        };
      };
      ios =
        let config = {
              allowUnfree = true;
              packageOverrides = p: {
                darwin = p.darwin // {
                  ios-cross = p.darwin.ios-cross.override {
                    # Depending on where ghcHEAD is in your nixpkgs checkout, you may need llvm 39 here instead
                    inherit (p.llvmPackages_39) llvm clang;
                  };
                };
                buildPackages = p.buildPackages // {
                  osx_sdk = p.buildPackages.callPackage ({ stdenv }:
                    let version = "10";
                    in stdenv.mkDerivation rec {
                    name = "iOS.sdk";

                    src = p.stdenv.cc.sdk;

                    unpackPhase    = "true";
                    configurePhase = "true";
                    buildPhase     = "true";
                    target_prefix = stdenv.lib.replaceStrings ["-"] ["_"] p.targetPlatform.config;
                    setupHook = ./setup-hook-ios.sh;

                    installPhase = ''
                      mkdir -p $out/
                      echo "Source is: $src"
                      cp -r $src/* $out/
                    '';

                    meta = with stdenv.lib; {
                      description = "The IOS OS ${version} SDK";
                      maintainers = with maintainers; [ copumpkin ];
                      platforms   = platforms.darwin;
                      license     = licenses.unfree;
                    };
                  }) {};
                };
                inherit all-cabal-hashes;
              };
            };
        in nixpkgs.lib.mapAttrs (_: args: nixpkgsFunc args) {
        simulator64 = {
          inherit system;
          crossSystem = {
            useIosPrebuilt = true;
            # You can change config/arch/isiPhoneSimulator depending on your target:
            # aarch64-apple-darwin14 | arm64  | false
            # arm-apple-darwin10     | armv7  | false
            # i386-apple-darwin11    | i386   | true
            # x86_64-apple-darwin14  | x86_64 | true
            config = "x86_64-apple-darwin14";
            arch = "x86_64";
            isiPhoneSimulator = true;
            sdkVer = iosSdkVersion;
            useiOSCross = true;
            openssl.system = "darwin64-x86_64-cc";
            libc = "libSystem";
          };
          inherit config;
        };
        arm64 = {
          inherit system;
          crossSystem = {
            useIosPrebuilt = true;
            # You can change config/arch/isiPhoneSimulator depending on your target:
            # aarch64-apple-darwin14 | arm64  | false
            # arm-apple-darwin10     | armv7  | false
            # i386-apple-darwin11    | i386   | true
            # x86_64-apple-darwin14  | x86_64 | true
            config = "aarch64-apple-darwin14";
            arch = "arm64";
            isiPhoneSimulator = false;
            sdkVer = iosSdkVersion;
            useiOSCross = true;
            openssl.system = "ios64-cross";
            libc = "libSystem";
          };
          inherit config;
        };
        armv7 = {
          inherit system;
          crossSystem = {
            useIosPrebuilt = true;
            # You can change config/arch/isiPhoneSimulator depending on your target:
            # aarch64-apple-darwin14 | arm64  | false
            # arm-apple-darwin10     | armv7  | false
            # i386-apple-darwin11    | i386   | true
            # x86_64-apple-darwin14  | x86_64 | true
            config = "arm-apple-darwin10";
            arch = "armv7";
            isiPhoneSimulator = false;
            sdkVer = iosSdkVersion;
            useiOSCross = true;
            openssl.system = "ios-cross";
            libc = "libSystem";
          };
          inherit config;
        };
      };
    };
    inherit (nixpkgs.haskell) lib;
    filterGit = builtins.filterSource (path: type: !(builtins.any (x: x == baseNameOf path) [".git"]));
    # All imports of sources need to go here, so that they can be explicitly cached
    sources = {
      ghcjs-boot = if builtins.pathExists ./ghcjs-boot/git.json then fetchgit (builtins.fromJSON (builtins.readFile ./ghcjs-boot/git.json)) else {
        name = "ghcjs-boot";
        outPath = filterGit ./ghcjs-boot;
      };
      shims = if builtins.pathExists ./shims/github.json then fetchFromGitHub (builtins.fromJSON (builtins.readFile ./shims/github.json)) else filterGit ./shims;
      ghcjs = if builtins.pathExists ./ghcjs/github.json then fetchFromGitHub (builtins.fromJSON (builtins.readFile ./ghcjs/github.json)) else filterGit ./ghcjs;
    };
    inherit (nixpkgs.stdenv.lib) optionals;
in with lib;
let overrideCabal = pkg: f: if pkg == null then null else lib.overrideCabal pkg f;
    exposeAeson = aeson: overrideCabal aeson (drv: {
      # Export all modules, and some additional functions
      preConfigure = ''
        sed -i '/^library/,/^test-suite/ s/other-modules://' *.cabal
        sed -i "/^module Data.Aeson.TH/,/) where/ { /^module/b; /) where/ { s/) where/, LookupField (..), parseTypeMismatch, parseTypeMismatch', valueConName) where/; b }; }" Data/Aeson/TH.hs
        ${drv.preConfigure or ""}
      '';
    });
    replaceSrc = pkg: src: version: overrideCabal pkg (drv: {
      inherit src version;
      sha256 = null;
      revision = null;
      editedCabalFile = null;
    });
    combineOverrides = old: new: (old // new) // {
      overrides = nixpkgs.lib.composeExtensions old.overrides new.overrides;
    };
    makeRecursivelyOverridable = x: old: x.override old // {
      override = new: makeRecursivelyOverridable x (combineOverrides old new);
    };
    foreignLibSmuggleHeaders = pkg: overrideCabal pkg (drv: {
      postInstall = ''
        cd dist/build/${pkg.pname}/${pkg.pname}-tmp
        for header in $(find . | grep '\.h''$'); do
          local dest_dir=$out/include/$(dirname "$header")
          mkdir -p "$dest_dir"
          cp "$header" "$dest_dir"
        done
      '';
    });
    cabal2nixResult = src: builtins.trace "cabal2nixResult is deprecated; use ghc.haskellSrc2nix or ghc.callCabal2nix instead" (ghc.haskellSrc2nix {
      name = "for-unknown-package";
      src = "file://${src}";
      sha256 = null;
    });
    addReflexTraceEventsFlag = if enableTraceReflexEvents
      then drv: appendConfigureFlag drv "-fdebug-trace-events"
      else drv: drv;
    # This is important to have for jsaddle, reflex, reflex-dom-core, and reflex-dom, at the very least; I suspect it's important for a lot more stuff, as well
    addExposeAllUnfoldingsToDrvGhc = if enableExposeAllUnfoldings
      then drv: drv // {
          configureFlags = (drv.configureFlags or []) ++ [
            "--ghc-options=-fexpose-all-unfoldings"
          ];
        }
      else drv: drv;
    addExposeAllUnfoldingsToDrvGhcjs = if enableExposeAllUnfoldings
      then drv: drv // {
          configureFlags = (drv.configureFlags or []) ++ [
            "--ghcjs-options=-fexpose-all-unfoldings"
          ];
        }
      else drv: drv;
    # The gi-libraries, by default, will use lots of overloading features of ghc that are still a bit too slow; this function disables them
    dontUseOverloads = p: appendConfigureFlag p "-f-overloaded-methods -f-overloaded-signals -f-overloaded-properties";
    dontUseCustomSetup = p: overrideCabal p (drv: {
      preCompileBuildDriver = assert (drv.preCompileBuildDriver or null) == null; ''
        rm Setup.hs || rm Setup.lhs
      '';
    });
    extendHaskellPackages = haskellPackages: makeRecursivelyOverridable haskellPackages {
      overrides = self: super:
        let reflexDom = import ./reflex-dom self nixpkgs;
            jsaddlePkgs = import ./jsaddle self;
            ghcjsDom = import ./ghcjs-dom self;
            addReflexOptimizerFlag = if useReflexOptimizer && (self.ghc.cross or null) == null
              then drv: appendConfigureFlag drv "-fuse-reflex-optimizer"
              else drv: drv;
        in {

        base-compat = self.callHackage "base-compat" "0.9.2" {};
        constraints = self.callHackage "constraints" "0.9" {};
        vector = doJailbreak super.vector;
        these = doJailbreak super.these;
        aeson-compat = doJailbreak super.aeson-compat;
        timezone-series = self.callCabal2nix "timezone-series" (fetchFromGitHub {
          owner = "ygale";
          repo = "timezone-series";
          rev = "9f42baf542c54ad554bd53582819eaa454ed633d";
          sha256 = "1axrx8lziwi6pixws4lq3yz871vxi81rib6cpdl62xb5bh9y03j6";
        }) {};
        timezone-olson = self.callCabal2nix "timezone-olson" (fetchFromGitHub {
          owner = "ygale";
          repo = "timezone-olson";
          rev = "aecec86be48580f23145ffb3bf12a4ae191d12d3";
          sha256 = "1xxbwb8z27qbcscbg5qdyzlc2czg5i3b0y04s9h36hfcb07hasnz";
        }) {};
        quickcheck-instances = doJailbreak super.quickcheck-instances;

        haskell-src-meta = self.callHackage "haskell-src-meta" "0.8.0.1" {};
        gtk2hs-buildtools = doJailbreak super.gtk2hs-buildtools;

        # Newer versions of 'hashable' don't work on the ghc 8.1.* that Android
        # and iOS are currently using.  Once they're upgraded to 8.2, we should
        # update 'hashable' to latest.
        hashable = doJailbreak (self.callHackage "hashable" "1.2.6.1" {});

        ########################################################################
        # Reflex packages
        ########################################################################
        reflex = addReflexTraceEventsFlag (addReflexOptimizerFlag (self.callPackage ./reflex {}));
        reflex-dom = addReflexOptimizerFlag (doJailbreak reflexDom.reflex-dom);
        reflex-dom-core = addReflexOptimizerFlag (doJailbreak reflexDom.reflex-dom-core);
        reflex-todomvc = self.callPackage ./reflex-todomvc {};
        reflex-aeson-orphans = self.callPackage ./reflex-aeson-orphans {};
        haven = self.callHackage "haven" "0.2.0.0" {};

        inherit (jsaddlePkgs) jsaddle jsaddle-clib jsaddle-wkwebview jsaddle-webkit2gtk jsaddle-webkitgtk;
        jsaddle-warp = dontCheck jsaddlePkgs.jsaddle-warp;

        jsaddle-dom = overrideCabal (self.callPackage ./jsaddle-dom {}) (drv: {
          # On macOS, the jsaddle-dom build will run out of file handles the first time it runs
          preBuild = ''./setup build || true'';
        });

        inherit (ghcjsDom) ghcjs-dom-jsffi;

        # TODO: Fix this in Cabal
        # When building a package with no haskell files, cabal haddock shouldn't fail
        ghcjs-dom-jsaddle = dontHaddock ghcjsDom.ghcjs-dom-jsaddle;
        ghcjs-dom = dontHaddock ghcjsDom.ghcjs-dom;


        ########################################################################
        # Tweaks
        ########################################################################
        gi-atk = dontUseOverloads super.gi-atk;
        gi-cairo = dontUseOverloads super.gi-cairo;
        gi-gdk = dontUseOverloads super.gi-gdk;
        gi-gdkpixbuf = dontUseOverloads super.gi-gdkpixbuf;
        gi-glib = dontUseOverloads (self.callPackage ./gi-glib.nix {});
        gi-gio = dontUseOverloads (self.callPackage ./gi-gio.nix {});
        gi-gtk = dontUseOverloads (self.callPackage ./gi-gtk.nix {
          gtk3 = nixpkgs.gnome3.gtk;
        });
        gi-javascriptcore = dontUseOverloads (self.callPackage ./gi-javascriptcore.nix {});
        gi-webkit2 = dontUseOverloads (self.callPackage ./gi-webkit2.nix {
          webkitgtk = nixpkgs.webkitgtk216x;
        });
        gi-gobject = dontUseOverloads super.gi-gobject;
        gi-pango = dontUseOverloads super.gi-pango;
        gi-soup = dontUseOverloads super.gi-soup;
        gi-webkit = dontUseOverloads super.gi-webkit;
        gi-gtksource = dontUseOverloads (super.gi-gtksource.override {
          inherit (nixpkgs.gnome3) gtksourceview;
        });

        haskell-gi-overloading = self.callPackage ./haskell-gi-overloading.nix {};

        webkit2gtk3-javascriptcore = super.webkit2gtk3-javascriptcore.override {
          webkitgtk = nixpkgs.webkitgtk216x;
        };

        cabal-macosx = overrideCabal super.cabal-macosx (drv: {
          src = fetchFromGitHub {
            owner = "obsidiansystems";
            repo = "cabal-macosx";
            rev = "b1e22331ffa91d66da32763c0d581b5d9a61481b";
            sha256 = "1y2qk61ciflbxjm0b1ab3h9lk8cm7m6ln5ranpf1lg01z1qk28m8";
          };
          doCheck = false;
        });

        ########################################################################
        # Fixes to be upstreamed
        ########################################################################
        foundation = if system == "i686-linux" then dontCheck super.foundation else super.foundation; # TODO: We should make sure these test failures get fixed
        MonadCatchIO-transformers = doJailbreak super.MonadCatchIO-transformers;
        blaze-builder-enumerator = doJailbreak super.blaze-builder-enumerator;
        process-extras = dontCheck super.process-extras;

        ########################################################################
        # Packages not in hackage
        ########################################################################
        concat = dontHaddock (dontCheck (self.callCabal2nix "concat" (fetchFromGitHub {
          owner = "conal";
          repo = "concat";
          rev = "24a4b8ccc883605ea2b0b4295460be2f8a245154";
          sha256 = "0mcwqzjk3f8qymmkbpa80l6mh6aa4vcyxky3gpwbnx19g721mj35";
        }) {}));

        superconstraints =
          # Remove override when assertion fails
          assert (super.superconstraints or null) == null;
          self.callPackage (self.haskellSrc2nix {
            name = "superconstraints";
            src = fetchurl {
              url = "https://hackage.haskell.org/package/superconstraints-0.0.1/superconstraints.cabal";
              sha256 = "0bgc8ldml3533522gp1x2bjiazllknslpl2rvdkd1k1zfdbh3g9m";
            };
            sha256 = "1gx9p9i5jli91dnvvrc30j04h1v2m3d71i8sxli6qrhplq5y63dk";
          }) {};
      } // (if enableLibraryProfiling then {
        mkDerivation = expr: super.mkDerivation (expr // { enableLibraryProfiling = true; });
      } else {});
    };
    overrideForGhc8_2_1 = haskellPackages: haskellPackages.override {
      overrides = self: super: {
        ChasingBottoms = dontCheck (self.callHackage "ChasingBottoms" "1.3.1.3" {});
        base-orphans = self.callHackage "base-orphans" "0.6" {};
        cabal-install = self.callCabal2nix "cabal-install" ((fetchFromGitHub {
          owner = "haskell";
          repo = "cabal";
          rev = "082cf2066b7206d3b12a9f92d832236e2484b4c1";
          sha256 = "0xzkwwim3chx9sd94b7n41ii9d51xzjlj48ikgn5dqjnxryz2r4k";
        }) + "/cabal-install") {};
        comonad = self.callHackage "comonad" "5.0.2" {};
        distributive = self.callHackage "distributive" "0.5.3" {};
        doctest = self.callHackage "doctest" "0.13.0" {};
        hackage-security = dontCheck (doJailbreak super.hackage-security);
        haddock = null;
        haddock-api = null; #dontCheck super.haddock-api;
        haddock-library = null; #dontHaddock (dontCheck (self.callPackage ./haddock-library.nix {}));
        hspec-meta = self.callHackage "hspec-meta" "2.4.4" {};
        primitive = self.callHackage "primitive" "0.6.2.0" {};
        profunctors = self.callHackage "profunctors" "5.2.1" {};
        semigroupoids = self.callHackage "semigroupoids" "5.2.1" {};
        shelly = doJailbreak super.shelly;
        syb = self.callHackage "syb" "0.7" {};
        vector = self.callHackage "vector" "0.12.0.1" {};
      };
    };
    overrideForGhcjs = haskellPackages: haskellPackages.override {
      overrides = self: super: {
        mkDerivation = drv: super.mkDerivation (addExposeAllUnfoldingsToDrvGhcjs drv);
        ghcWithPackages = selectFrom: self.callPackage (nixpkgs.path + "/pkgs/development/haskell-modules/with-packages-wrapper.nix") {
          inherit (self) llvmPackages;
          haskellPackages = self;
          packages = selectFrom self;
          ${if useReflexOptimizer then "ghcLibdir" else null} = "${ghc.ghcWithPackages (p: [ p.reflex ])}/lib/${ghc.ghc.name}";
        };

        ghc = super.ghc // {
          withPackages = self.ghcWithPackages;
        };

        diagrams-lib = dontCheck super.diagrams-lib;

      } // (if useTextJSString then overridesForTextJSString self super else {});
    };
    stage2Script = nixpkgs.runCommand "stage2.nix" {
      GEN_STAGE2 = builtins.readFile (nixpkgs.path + "/pkgs/development/compilers/ghcjs/gen-stage2.rb");
      buildCommand = ''
        echo "$GEN_STAGE2" > gen-stage2.rb && chmod +x gen-stage2.rb
        patchShebangs .
        ./gen-stage2.rb "${sources.ghcjs-boot}" >"$out"
      '';
      nativeBuildInputs = with nixpkgs; [
        ruby cabal2nix
      ];
    } "";
    ghcjsCompiler = ghc.callPackage (nixpkgs.path + "/pkgs/development/compilers/ghcjs/base.nix") {
      bootPkgs = ghc;
      ghcjsSrc = sources.ghcjs;
      ghcjsBootSrc = sources.ghcjs-boot;
      shims = sources.shims;
      stage2 = import stage2Script;
    };
    ghcjsPackages = nixpkgs.haskell.packages.ghcjs.override {
      ghc = ghcjsCompiler;
    };
    ghcjs = overrideForGhcjs (extendHaskellPackages ghcjsPackages);
    overrideForGhcHEAD = haskellPackages: haskellPackages.override {
      overrides = self: super: {
        th-expand-syns = doJailbreak super.th-expand-syns;
        ChasingBottoms = doJailbreak super.ChasingBottoms;
        base-orphans = dontCheck super.base-orphans;
        bifunctors = dontCheck super.bifunctors;
        HTTP = doJailbreak super.HTTP;
        newtype-generics = doJailbreak super.newtype-generics;
        extra = replaceSrc super.extra (fetchFromGitHub {
          owner = "ndmitchell";
          repo = "extra";
          rev = "22b0e6aa6077b2d969e8b8ac613f5a3455d9e88d";
          sha256 = "0milbw2azkj22rqacrnd0x4wh65qfrl3nhbmwfxzmdrsc2la3bkh";
        }) "1.5.2";
      };
    };
    overrideForGhc = haskellPackages: haskellPackages.override {
      overrides = self: super: {
        mkDerivation = drv: super.mkDerivation (addExposeAllUnfoldingsToDrvGhc drv);
        ########################################################################
        # Synchronize packages with ghcjs
        ########################################################################
        # aeson-0.11.2.0's tests can't build with QuickCheck >= 2.9, because
        # some instances have been added to QuickCheck which overlap with ones
        # defined by aeson.  This can probably be removed once ghcjs-boot has
        # updated to aeson >= 0.11.2.1.
        aeson = let version = (import stage2Script { ghcjsBoot = null; } { inherit (self) callPackage; }).aeson.version;
          in dontCheck (self.callPackage (self.hackage2nix "aeson" version) {});
      };
    };
    overrideForGhc8 = haskellPackages: haskellPackages.override {
      overrides = self: super: {
        ghcjs-prim = null;
        ghcjs-json = null;
      };
    };
    overrideForGhc7 = haskellPackages: haskellPackages.override {
      overrides = self: super: {
        cereal = dontCheck super.cereal; # cereal's test suite requires a newer version of bytestring than this haskell environment provides
      };
    };
    overrideForGhc7_8 = haskellPackages: (overrideForGhc7 haskellPackages).override {
      overrides = self: super: {
        mkDerivation = drv: super.mkDerivation (drv // {
          enableSplitObjs = false; # Split objects with template haskell doesn't work on ghc 7.8
        });
        MemoTrie = addBuildDepend super.MemoTrie self.void;
        generic-deriving = dontHaddock super.generic-deriving;
        bifunctors = dontHaddock super.bifunctors;
        cereal = dontCheck super.cereal; # cereal's test suite requires a newer version of bytestring than this haskell environment provides
      };
    };
    disableTemplateHaskell = haskellPackages: haskellPackages.override {
      overrides = self: super: {
        # Aeson's TH splices refer to names that aren't exported
        aeson = exposeAeson super.aeson;

        # These custom Setup.lhs files don't work
        distributive = dontUseCustomSetup super.distributive;
        comonad = dontUseCustomSetup super.comonad;
        semigroupoids = dontUseCustomSetup (appendConfigureFlag super.semigroupoids "-f-doctests");

        wai-websockets = appendConfigureFlag super.wai-websockets "-f-example";
        cryptonite = appendConfigureFlag super.cryptonite "-f-integer-gmp";

        profunctors = overrideCabal super.profunctors (drv: {
          preConfigure = ''
            sed -i 's/^{-# ANN .* #-}$//' src/Data/Profunctor/Unsafe.hs
          '';
        });
        fgl = overrideCabal super.fgl (drv: {
          preConfigure = ''
            sed -i 's/^{-# ANN .* #-}$//' $(find Data -name '*.hs')
          '';
        });
        lens = overrideCabal super.lens (drv: {
          preConfigure = ''
            sed -i 's/^{-# ANN .* #-}$//' $(find src -name '*.hs')
          '';
          doCheck = false;
          jailbreak = true;
        });

        reflex = super.reflex.override {
          useTemplateHaskell = false;
        };
        reflex-dom-core = appendConfigureFlag super.reflex-dom-core "-f-use-template-haskell";
        # TODO: this is probably a good idea too
        #alex = self.ghc.bootPkgs.alex;
        happy = self.ghc.bootPkgs.happy;

        # Disabled for now (jsaddle-wkwebview will probably be better on iOS)
        jsaddle-warp = null;
        # Disable these because these on iOS
        jsaddle-webkitgtk = null;
        jsaddle-webkit2gtk = null;
      };
    };
    overrideForGhcAndroid = haskellPackages: haskellPackages.override {
      overrides = self: super: {
        ghc = super.ghc // {
          bootPkgs = super.ghc.bootPkgs.override {
            overrides = self: super: {
              Cabal = appendPatch (self.callHackage "Cabal" "2.0.0.2" {}) ./Cabal-Allow-any-arch-with-linux-for-foreign-libs.patch;
            };
          };
        };
        android-activity = self.callPackage ./android/android-activity {
          inherit (nixpkgs) jdk;
        };

        syb = overrideCabal super.syb (drv: { jailbreak = true; });
        cabal-doctest = null;

        # Break version bounds on base for GHC HEAD.
        lifted-async = doJailbreak super.lifted-async;
        safe-exceptions = doJailbreak super.safe-exceptions;

        mkDerivation = drv: super.mkDerivation (drv // {
          doHaddock = false;
          dontStrip = true;
          enableSharedExecutables = false;
          configureFlags = (drv.configureFlags or []) ++ [
            "--ghc-option=-fPIC"
            "--ghc-option=-optc-fPIC"
            "--ghc-option=-optc-shared"
            "--ghc-option=-optl-shared"
          ];
        });
      };
    };
    overrideForGhcIOS = haskellPackages: haskellPackages.override {
      overrides = self: super: {
        ghcjs-prim = null;
        ghcjs-json = null;
        derive = null;
        focus-http-th = null;
        th-lift-instances = null;
        websockets = null;
        wai = null;
        warp = null;
        wai-app-static = null;

        cabal-doctest = null;
        syb = overrideCabal super.syb (drv: { jailbreak = true; });

        reflex-todomvc = overrideCabal super.reflex-todomvc (drv: {
            postFixup = ''
                mkdir $out/reflex-todomvc.app
                cp reflex-todomvc.app/* $out/reflex-todomvc.app/
                cp $out/bin/reflex-todomvc $out/reflex-todomvc.app/
            '';
        });
        cabal-macosx = null;
        mkDerivation = drv: super.mkDerivation (drv // {
          doHaddock = false;
          enableSharedLibraries = false;
          enableSharedExecutables = false;
        });
      };
    };
    overridesForTextJSString = self: super: {
      text = self.callCabal2nix "text" (fetchFromGitHub {
        owner = "luigy";
        repo = "text";
        rev = "6cc95ebb07c07001666d84ace5c13caefaaa0cad";
        sha256 = "1zplzy9mfpwjrk5l22gmla1vmk7wmwmgmjfk64b57ysn7madlv19";
      }) {};
      jsaddle = overrideCabal super.jsaddle (drv: {
        patches = (drv.patches or []) ++ [
          ./jsaddle-text-jsstring.patch
        ];
        buildDepends = (drv.buildDepends or []) ++ [
          self.ghcjs-json
        ];
      });
      ghcjs-json = self.callCabal2nix "ghcjs-json" (fetchFromGitHub {
        owner = "obsidiansystems";
        repo = "ghcjs-json";
        rev = "3a6e1e949aced800d32e0683a107f5387295f3a6";
        sha256 = "1pjsvyvy6ac3358db19iwgbmsmm0si2hzh2ja1hclq43q6d80yij";
      }) {};
      ghcjs-base = overrideCabal super.ghcjs-base (drv: {
        src = fetchFromGitHub {
          owner = "luigy";
          repo = "ghcjs-base";
          rev = "8569f5d541aa846f2130ff789d19bcd55ea41d2a";
          sha256 = "1b1fyqgn7jxh4rawgxidacafg6jwfdfcidyh93z6a6lhmm5qaq3n";
        };
        libraryHaskellDepends = with self; [
          base bytestring containers deepseq dlist ghc-prim
          ghcjs-prim integer-gmp primitive time
          transformers vector
        ];
      });
      attoparsec = overrideCabal super.attoparsec (drv: {
        src = fetchFromGitHub {
          owner = "luigy";
          repo = "attoparsec";
          rev = "e766a754811042f061b6b4498137d2ad28e207a8";
          sha256 = "106fn187hw9z3bidbkp7r4wafmhk7g2iv2k0hybirv63f8727x3x";
        };
      });
      hashable = addBuildDepend (self.callCabal2nix "hashable" (fetchFromGitHub {
        owner = "luigy";
        repo = "hashable";
        rev = "97a6fc77b028b4b3a7310a5c2897b8611e518870";
        sha256 = "1rl55p5y0mm8a7hxlfzhhgnnciw2h63ilxdaag3h7ypdx4bfd6rs";
      }) {}) self.text;
      conduit-extra = overrideCabal super.conduit-extra (drv: {
        src = "${fetchFromGitHub {
          owner = "luigy";
          repo = "conduit";
          rev = "aeb20e4eb7f7bfc07ec401c82821cbb04018b571";
          sha256 = "10kz2m2yxyhk46xdglj7wdn5ba2swqzhyznxasj0jvnjcnv3jriw";
        }}/conduit-extra";
      });
      double-conversion = overrideCabal super.double-conversion (drv: {
        src = fetchFromGitHub {
          owner = "obsidiansystems";
          repo = "double-conversion";
          rev = "0f9ddde468687d25fa6c4c9accb02a034bc2f9c3";
          sha256 = "0sjljf1sbwalw1zycpjf6bqhljag9i1k77b18b0fd1pzrc29wnks";
        };
      });
      say = overrideCabal super.say (drv: {
        patches = (drv.patches or []) ++ [
          ./say-text-jsstring.patch
        ];
        buildDepends = (drv.buildDepends or []) ++ [
          self.ghcjs-base
        ];
      });
    };
  ghcHEAD = overrideForGhcHEAD (overrideForGhc8 (overrideForGhc (extendHaskellPackages nixpkgs.pkgs.haskell.packages.ghcHEAD)));
  patchGhc8 = haskellPackages: haskellPackages.override {
    overrides = self: super: {};
    ghc = haskellPackages.ghc.overrideDerivation (drv: {
      patches = ([]) ++ [ ./optimize-superclass-constraints.patch ];
    });
  };
  ghc8_2_1 = overrideForGhc8_2_1 (overrideForGhc8 (overrideForGhc (extendHaskellPackages nixpkgs.pkgs.haskell.packages.ghc821)));
  ghc = overrideForGhc8 (overrideForGhc (extendHaskellPackages nixpkgs.pkgs.haskell.packages.ghc802));
  ghc8_0_1 = overrideForGhc8 (overrideForGhc (extendHaskellPackages nixpkgs.pkgs.haskell.packages.ghc801));
  ghc7 = overrideForGhc7 (overrideForGhc (extendHaskellPackages nixpkgs.pkgs.haskell.packages.ghc7103));
  ghc7_8 = overrideForGhc7_8 (overrideForGhc (extendHaskellPackages nixpkgs.pkgs.haskell.packages.ghc784));
  ghcIosSimulator64 = overrideForGhcIOS (overrideForGhc8_2_1 (overrideForGhc8 (overrideForGhc (extendHaskellPackages nixpkgsCross.ios.simulator64.pkgs.haskell.packages.ghc821))));
  ghcAndroidArm64 = overrideForGhcAndroid (disableTemplateHaskell (overrideForGhc8_2_1 (overrideForGhc8 (overrideForGhc (extendHaskellPackages nixpkgsCross.android.arm64Impure.pkgs.haskell.packages.ghc821)))));
  ghcAndroidArmv7a = overrideForGhcAndroid (disableTemplateHaskell (overrideForGhc8_2_1 (overrideForGhc8 (overrideForGhc (extendHaskellPackages nixpkgsCross.android.armv7aImpure.pkgs.haskell.packages.ghc821)))));
  ghcIosArm64 = overrideForGhcIOS (disableTemplateHaskell (overrideForGhc8_2_1 (overrideForGhc8 (overrideForGhc (extendHaskellPackages nixpkgsCross.ios.arm64.pkgs.haskell.packages.ghc821)))));
  ghcIosArmv7 = overrideForGhcIOS (disableTemplateHaskell (overrideForGhc8_2_1 (overrideForGhc8 (overrideForGhc (extendHaskellPackages nixpkgsCross.ios.armv7.pkgs.haskell.packages.ghc821)))));
  #TODO: Separate debug and release APKs
  #TODO: Warn the user that the android app name can't include dashes
  android = androidWithHaskellPackages { inherit ghcAndroidArm64 ghcAndroidArmv7a; };
  androidWithHaskellPackages = { ghcAndroidArm64, ghcAndroidArmv7a }: import ./android { inherit nixpkgs nixpkgsCross ghcAndroidArm64 ghcAndroidArmv7a overrideCabal; };
in let this = rec {
  inherit nixpkgs nixpkgsCross overrideCabal extendHaskellPackages foreignLibSmuggleHeaders stage2Script ghc ghcHEAD ghc8_2_1 ghc8_0_1 ghc7 ghc7_8 ghcIosSimulator64 ghcIosArm64 ghcIosArmv7 ghcAndroidArm64 ghcAndroidArmv7a android androidWithHaskellPackages;
  androidReflexTodomvc = android.buildApp {
    package = p: p.reflex-todomvc;
    executableName = "reflex-todomvc";
    applicationId = "org.reflexfrp.todomvc";
    displayName = "Reflex TodoMVC";
  };
  setGhcLibdir = ghcLibdir: inputGhcjs:
    let libDir = "$out/lib/ghcjs-${inputGhcjs.version}";
        ghcLibdirLink = nixpkgs.stdenv.mkDerivation {
          name = "ghc_libdir";
          inherit ghcLibdir;
          buildCommand = ''
            mkdir -p ${libDir}
            echo "$ghcLibdir" > ${libDir}/ghc_libdir_override
          '';
        };
    in inputGhcjs // {
    outPath = nixpkgs.buildEnv {
      inherit (inputGhcjs) name;
      paths = [ inputGhcjs ghcLibdirLink ];
      postBuild = ''
        mv ${libDir}/ghc_libdir_override ${libDir}/ghc_libdir
      '';
    };
  };

  inherit ghcjs ghcjsCompiler;
  platforms = [
    "ghcjs"
    "ghc"
  ] ++ (optionals (system == "x86_64-linux") [
#    "ghcAndroidArm64"
#    "ghcAndroidArmv7a"
  ]) ++ (optionals nixpkgs.stdenv.isDarwin [
    "ghcIosArm64"
  ]);

  attrsToList = s: map (name: { inherit name; value = builtins.getAttr name s; }) (builtins.attrNames s);
  mapSet = f: s: builtins.listToAttrs (map ({name, value}: {
    inherit name;
    value = f value;
  }) (attrsToList s));
  mkSdist = pkg: pkg.override {
    mkDerivation = drv: ghc.mkDerivation (drv // {
      postConfigure = ''
        ./Setup sdist
        mkdir "$out"
        mv dist/*.tar.gz "$out/${drv.pname}-${drv.version}.tar.gz"
        exit 0
      '';
    });
  };
  sdists = mapSet mkSdist ghc;
  mkHackageDocs = pkg: pkg.override {
    mkDerivation = drv: ghc.mkDerivation (drv // {
      postConfigure = ''
        ./Setup haddock --hoogle --hyperlink-source --html --html-location='/package/${drv.pname}-${drv.version}/docs' --contents-location='/package/${drv.pname}-${drv.version}' --haddock-option=--built-in-themes
        cd dist/doc/html
        mv "${drv.pname}" "${drv.pname}-${drv.version}-docs"
        mkdir "$out"
        tar cz --format=ustar -f "$out/${drv.pname}-${drv.version}-docs.tar.gz" "${drv.pname}-${drv.version}-docs"
        exit 0
      '';
    });
  };
  hackageDocs = mapSet mkHackageDocs ghc;
  mkReleaseCandidate = pkg: nixpkgs.stdenv.mkDerivation (rec {
    name = pkg.name + "-rc";
    sdist = mkSdist pkg + "/${pkg.pname}-${pkg.version}.tar.gz";
    docs = mkHackageDocs pkg + "/${pkg.pname}-${pkg.version}-docs.tar.gz";

    builder = builtins.toFile "builder.sh" ''
      source $stdenv/setup

      mkdir "$out"
      echo -n "${pkg.pname}-${pkg.version}" >"$out/pkgname"
      ln -s "$sdist" "$docs" "$out"
    '';

    # 'checked' isn't used, but it is here so that the build will fail if tests fail
    checked = overrideCabal pkg (drv: {
      doCheck = true;
      src = sdist;
    });
  });
  releaseCandidates = mapSet mkReleaseCandidate ghc;

  androidDevTools = [
    ghc.haven
    nixpkgs.maven
  ];

  # Tools that are useful for development under both ghc and ghcjs
  generalDevTools = haskellPackages:
    let nativeHaskellPackages = ghc;
    in [
    nativeHaskellPackages.Cabal
    nativeHaskellPackages.cabal-install
    nativeHaskellPackages.ghcid
    nativeHaskellPackages.hlint
    nixpkgs.cabal2nix
    nixpkgs.curl
    nixpkgs.nix-prefetch-scripts
    nixpkgs.nodejs
    nixpkgs.pkgconfig
    nixpkgs.closurecompiler
  ] ++ (if builtins.compareVersions haskellPackages.ghc.version "7.10" >= 0 then [
    nativeHaskellPackages.stylish-haskell # Recent stylish-haskell only builds with AMP in place
  ] else []) ++ androidDevTools;

  nativeHaskellPackages = haskellPackages:
    if haskellPackages.isGhcjs or false
    then haskellPackages.ghc
    else haskellPackages;

  workOn = haskellPackages: package: (overrideCabal package (drv: {
    buildDepends = (drv.buildDepends or []) ++ generalDevTools (nativeHaskellPackages haskellPackages);
  })).env;

  workOnMulti = env: packageNames: nixpkgs.runCommand "shell" {
    buildInputs = [
      (env.ghc.withPackages (packageEnv: builtins.concatLists (map (n: (packageEnv.${n}.override { mkDerivation = x: { out = builtins.filter (p: builtins.all (nameToAvoid: (p.pname or "") != nameToAvoid) packageNames) ((x.buildDepends or []) ++ (x.libraryHaskellDepends or []) ++ (x.executableHaskellDepends or []) ++ (x.testHaskellDepends or [])); }; }).out) packageNames)))
    ] ++ generalDevTools env;
  } "";

  # A simple derivation that just creates a file with the names of all of its inputs.  If built, it will have a runtime dependency on all of the given build inputs.
  pinBuildInputs = drvName: buildInputs: otherDeps: nixpkgs.runCommand drvName {
    buildCommand = ''
      mkdir "$out"
      echo "$propagatedBuildInputs $buildInputs $nativeBuildInputs $propagatedNativeBuildInputs $otherDeps" > "$out/deps"
    '';
    inherit buildInputs otherDeps;
  } "";

  # The systems that we want to build for on the current system
  cacheTargetSystems = [
    "x86_64-linux"
    "i686-linux"
    "x86_64-darwin"
  ];

  isSuffixOf = suffix: s:
    let suffixLen = builtins.stringLength suffix;
    in builtins.substring (builtins.stringLength s - suffixLen) suffixLen s == suffix;

  reflexEnv = platform:
    let haskellPackages = builtins.getAttr platform this;
        ghcWithStuff = if platform == "ghc" || platform == "ghcjs" then haskellPackages.ghcWithHoogle else haskellPackages.ghcWithPackages;
    in ghcWithStuff (p: import ./packages.nix { haskellPackages = p; inherit platform; });

  tryReflexPackages = generalDevTools ghc ++ builtins.map reflexEnv platforms;

  demoVM = (import "${nixpkgs.path}/nixos" {
    configuration = {
      imports = [
        "${nixpkgs.path}/nixos/modules/virtualisation/virtualbox-image.nix"
        "${nixpkgs.path}/nixos/modules/profiles/demo.nix"
      ];
      environment.systemPackages = tryReflexPackages;
    };
  }).config.system.build.virtualBoxOVA;

  inherit lib cabal2nixResult sources;
}; in this
