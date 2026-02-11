# Changelog

## [1.1.0](https://github.com/dbehnke/urfd-tilt/compare/v1.0.0...v1.1.0) (2026-02-11)


### Features

* add complete production deployment system ([d2db34c](https://github.com/dbehnke/urfd-tilt/commit/d2db34c1a6ca3d1c9e7eed5daf620bc7acf025c1))
* enable web voice transmission with live dashboard updates ([2b25721](https://github.com/dbehnke/urfd-tilt/commit/2b2572130faef3b0e823bd0fd5d00f29c13bf485))
* **packer:** automate unattended Debian VM package validation ([b7e0b0f](https://github.com/dbehnke/urfd-tilt/commit/b7e0b0f29e421a9f7b0f30d08d27288792e7bcb2))
* **release:** add release-please flow and semver-safe package versions ([ed84a74](https://github.com/dbehnke/urfd-tilt/commit/ed84a748f85f3637ce6fd32965ef3e94f52ce84d))


### Bug Fixes

* **ci:** skip missing units and normalize service state checks ([3c3ba51](https://github.com/dbehnke/urfd-tilt/commit/3c3ba51d5bb407e448bae13b934782ac64c40fe8))
* correct README inaccuracies found in audit ([ca199b8](https://github.com/dbehnke/urfd-tilt/commit/ca199b81704187fa5343f14efbba9e5411dac064))
* correct repository layout to show submodules in src/ directory ([39bba06](https://github.com/dbehnke/urfd-tilt/commit/39bba065851706e122eccf4261c18663591c67da))
* correct URFD-TCD connection protocol in diagram (TCP -&gt; NNG) ([eaae309](https://github.com/dbehnke/urfd-tilt/commit/eaae309a2164e5a9ec788cbcdea7f4c0bc2419d5))
* **packaging:** build allstar-nexus frontend assets before go embed ([0f4dc30](https://github.com/dbehnke/urfd-tilt/commit/0f4dc3047aafddbaa0ded7c5e1a4b7f6d0d16aa1))
* **packaging:** generate and remap meta-package doc inputs ([9dda47f](https://github.com/dbehnke/urfd-tilt/commit/9dda47fadef169b6a22c3b576218fb28cf1ec8ef))
* **packaging:** normalize curl dependency and align docs ([2def861](https://github.com/dbehnke/urfd-tilt/commit/2def861c1860645dac647ca2cf0d2a49630bc8e9))
* **packaging:** produce urfd and allstar packages in CI builds ([a643b21](https://github.com/dbehnke/urfd-tilt/commit/a643b21a88484721ec35d535943312e67df61007))
* **packaging:** remap package-specific docs paths to generated doc staging ([ceadf99](https://github.com/dbehnke/urfd-tilt/commit/ceadf99c97b893b40ae6858d994739fc660a15e9))
* **packaging:** resolve allstar embed build package path before docker run ([ffac8c7](https://github.com/dbehnke/urfd-tilt/commit/ffac8c7655bdf31d45e81bd44d152f1e3ee9a823))
* **packaging:** rewrite package-scoped docs paths for nfpm temp configs ([e13c9ea](https://github.com/dbehnke/urfd-tilt/commit/e13c9ea8562eb04f6c9b0f33ae38641d058f6a5d))
* **packaging:** stage lintian-overrides into per-package docs ([991606d](https://github.com/dbehnke/urfd-tilt/commit/991606d6f403cb2761d6424d1ea96c89958436e9))
* PTT recording notifications and real-time UI updates ([5eb7a21](https://github.com/dbehnke/urfd-tilt/commit/5eb7a2123cc09d072bfc77bb869693f13f841b97))
* update dashboard submodule with NNG voice client timeout fix ([56407c1](https://github.com/dbehnke/urfd-tilt/commit/56407c1cabf650989bafdca4f243cccaaff1cce5))
