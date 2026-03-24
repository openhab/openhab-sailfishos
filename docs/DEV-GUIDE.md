# Development and Contribution Guide

## Contribution guidelines
We welcome contributions to the openHAB client for Sailfish OS! Whether it's bug fixes, new features, or improvements to documentation, your contributions are valuable. 

Please follow these guidelines to ensure a smooth contribution process:
- Please read and agree to the [openHAB Contribution](https://next.openhab.org/docs/developer/contributing.html) Guidelines before submitting a pull request.
- Especially, each commit needs to be **signed-off** by the contributor, which is a declaration that the contribution is made in accordance with the Developer Certificate of Origin (DCO). This is a requirement for all contributions to openHAB. You can find more information about signing your work in the [contribution guidelines](https://next.openhab.org/docs/developer/contributing.html#sign-your-work).

## Getting Started

### Setting up development environment

If you want to contribute to Sailfish OS application we are here to help you to set up development environment. openHAB client for Sailfish OS is developed using Sailfish IDE.

- Download and install [Sailfish IDE](https://docs.sailfishos.org/Tools/Sailfish_SDK/Installation/)

You are ready to contribute!

### Running the app in the emulator
To run the app in the emulator, follow these steps:
1. Open Sailfish IDE, klick on "File", "open File or Project" and select the `harbour-openhab.pro` file.
2. Adjust on the left sidebar the mode to "Debug" and select the emulator "Sailfishos-XXXXXX-i486"
3. Klick on Build the project
4. Klick on Run the project
5. Now the Emulator should start and you are ready to debug.

Please checkout also official documentation on [Sailfishos - Your first app](https://docs.sailfishos.org/Develop/Apps/Your_First_App/) for more information.

## Localization

All language/regional translations are managed here [translations/*](/translations/) in the GitHub repository.
If you want to contribute translations, please submit them as pull requests against the `translations/*/openHAB-{language-code}.ts` files directly.

- Go to folder translations.
- If there is a file with your language code, click on it and select the edit icon
- If not:
    - Click on harbour-openHAB.ts file
    - Select copy icon (Copy raw file)
    - Go back, click Add file -> Create new file
    - Enter openHAB-xx.ts replacing xx with your language code as the name. For example, de for german
    - Paste the copied file in the new file's contents
- replace:

  ```xml
  <source>Save</source>
  <translation type="unfinished"></translation>
  ```

  with the correct translation for your language (remove "type="unfinished" and add the translation in between the <translation> tags). For example, for german:

  ```xml
  <source>Save</source>
  <translation>Speichern</translation>
  ```

Thanks for your consideration and contribution!

## Checks to be done before submitting a pull request
* Decide on the next version number for the app. Please follow [Semantic Versioning](https://rpm.org/docs/6.0.x/man/rpm-version.7) and update the VERSION and RELEASE in the `harbour-openhab.spec` and `harbour-openhab.pro` files.
* Update the [CHANGELOG](/rpm/harbour-openhab.changes) with a description of the changes you have made.
* Check folder [translations](/translations/) for missing translations and add them if needed.
* Are new permissions needed for the app? If so, please add them to the `harbour-openhab.desktop`.
* If you have added new features, please update:
  * [USAGE.md](/docs/USAGE.md) documentation
  * [README.md](/docs/README.md) documentation
  * add new screenshots - if needed - to the [images](/docs/images/) folder and update the screenshots in the documentation accordingly.
* Do we need to update our privacy policy? If so, please update the [PRIVACY_POLICY](https://github.com/openhabfoundation/openhabfoundation.github.io/blob/main/privacy.md) documentation and raise a Pull Request.
