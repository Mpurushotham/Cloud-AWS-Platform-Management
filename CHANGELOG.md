## [1.0.3](https://github.com/Mpurushotham/Cloud-AWS-Platform-Management/compare/v1.0.2...v1.0.3) (2026-07-28)

### Bug Fixes

* **ci:** correct prowler framework names and retarget drift detection ([e6c298c](https://github.com/Mpurushotham/Cloud-AWS-Platform-Management/commit/e6c298c874e95b1dece7ec71680cabfd34d19a30))

## [1.0.2](https://github.com/Mpurushotham/Cloud-AWS-Platform-Management/compare/v1.0.1...v1.0.2) (2026-07-28)

### Bug Fixes

* **ci:** skip the branch guard hook in ci rather than failing on it ([4293fc1](https://github.com/Mpurushotham/Cloud-AWS-Platform-Management/commit/4293fc1aec0e99deb765a085f61be6286e37be93))

## [1.0.1](https://github.com/Mpurushotham/Cloud-AWS-Platform-Management/compare/v1.0.0...v1.0.1) (2026-07-28)

### Bug Fixes

* **ci:** remove non-existent upper() and repair the drift job matrix ([1b4e5eb](https://github.com/Mpurushotham/Cloud-AWS-Platform-Management/commit/1b4e5ebe4825e5bb456576185d5f48df45ebf4c3))

## 1.0.0 (2026-07-28)

### Features

* **bootstrap:** add deployable free-tier lab profile with decision records ([37d4a58](https://github.com/Mpurushotham/Cloud-AWS-Platform-Management/commit/37d4a58907696734fc44b8b1276d3d67df38fad4))

### Bug Fixes

* **ci:** allowlist reviewed gitleaks false positives, replace tfsec with trivy ([ba94090](https://github.com/Mpurushotham/Cloud-AWS-Platform-Management/commit/ba94090a3ff78ec6178ce9b083015c59b9681d6b))
* **ci:** honour scanner configs and scope pre-commit terraform hooks ([72f84c3](https://github.com/Mpurushotham/Cloud-AWS-Platform-Management/commit/72f84c3d662e92481e8f684f8cde419a6c0f789d))
* **ci:** make pre-commit pass by fixing its config and my own duplicate key ([b6d75b8](https://github.com/Mpurushotham/Cloud-AWS-Platform-Management/commit/b6d75b86a3a31736eb90a32bee6000cc6cb9b068))
* **ci:** pin actions to shas, repair scanners, enable dependabot ([0471a94](https://github.com/Mpurushotham/Cloud-AWS-Platform-Management/commit/0471a94d1196b8bae95716164257743d333b94fe))
* **ci:** refresh grype db, stop double-gating on trivy, trim pre-commit ([0d07ac8](https://github.com/Mpurushotham/Cloud-AWS-Platform-Management/commit/0d07ac8cc271c35328ef27fea0fb383d1cd0f87c))
* **ci:** repair release, sbom, infracost, tflint and cdk tests ([a0b8b19](https://github.com/Mpurushotham/Cloud-AWS-Platform-Management/commit/a0b8b196447d7040005e683207acf50f10369928))
* **ci:** restore trivy report-only gate, refresh grype db in-step ([ecca50b](https://github.com/Mpurushotham/Cloud-AWS-Platform-Management/commit/ecca50bc5865db4a6a59fd64fbe7fe65421cd1d2))
* **ci:** update grype to a release whose db schema still publishes ([f6266e0](https://github.com/Mpurushotham/Cloud-AWS-Platform-Management/commit/f6266e0484bcae8febdcec9cb65c163bfcb8d683))
* **monitoring:** stop the cost guard from being the only cost ([ae9dc1d](https://github.com/Mpurushotham/Cloud-AWS-Platform-Management/commit/ae9dc1dbcf2656f7bd1765ca61e2077c34048f64))
* **security:** address checkov findings on the lab profile ([bb71054](https://github.com/Mpurushotham/Cloud-AWS-Platform-Management/commit/bb710546f5e171cd71a4f1a62b80dbae75c621e9))
* **security:** document the unscopable actions in the user access policy ([eabb64f](https://github.com/Mpurushotham/Cloud-AWS-Platform-Management/commit/eabb64f73fe088a04f5b11e8d0129687a0da4f24))
* **security:** grant cap-prowler the cost and budget reads its checks need ([836205d](https://github.com/Mpurushotham/Cloud-AWS-Platform-Management/commit/836205db8246ebec9dfae3efc179a1d7b9ca2e6a))
* **security:** let the iam user refresh its own aws login session ([443f5c3](https://github.com/Mpurushotham/Cloud-AWS-Platform-Management/commit/443f5c38d4f32e7bd7a3785e48c11031fcc5a5d5))
* **security:** repin trivy-action off a compromised release, fix rego imports ([1810e60](https://github.com/Mpurushotham/Cloud-AWS-Platform-Management/commit/1810e60f99da8d205c051ca236b862a60d79a9cb))
* **security:** scope vulnerability scanners and clear checkov on lab code ([3c4bc52](https://github.com/Mpurushotham/Cloud-AWS-Platform-Management/commit/3c4bc5223cffadcf1d134194e4412e4d00902d76))
* **terraform:** repair three unvalidatable modules and implement the waf ([a80baa4](https://github.com/Mpurushotham/Cloud-AWS-Platform-Management/commit/a80baa49c03278872ede16ded7d26dde84fd781a))
