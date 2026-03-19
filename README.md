<p align="center">
   <br>
    <img alt="Logo" src="icons/harbour-openhab.svg" width="100">
    <br>
    <b>openHAB client for Sailfish OS</b>
</p>

## Introduction

This app is a native client for openHAB which allows easy access to your sitemaps.
The documentation is available at [www.openhab.org/docs/](https://www.openhab.org/docs/).

<a href="https://github.com/openhab/openhab-sailfishos/releases"><img src="docs/images/get-it-on-jollaStore.png" alt="Get it on Jolla Store" height="80"></a>
<a href="https://openrepos.net/content/openhabfoundationev/openhab-smart-home-automation"><img src="docs/images/get-it-on-openrepos.png" alt="Get it on OpenRepos" height="55"></a>
<a href="https://github.com/openhab/openhab-sailfishos/releases"><img src="docs/images/direct-apk-download.png" alt="Get it on GitHub" height="80"></a>


## Features
* Display your sitemaps and widgets and control your devices from your mobile device
* Supported widgets/element-types: Frame, Text, Group, Switch, Switches with Button-Mappings, Selections, Slider, Rollershutter
* Customizable CoverActions via Settings

<img src="docs/images/main-ui.png" alt="Main UI" width=200px> <img src="docs/images/sitemap-1.png" alt="Settings" width=200px> <img src="docs/images/sitemap-2.png" alt="Sitemap view" width=200px>

For more screenshots, see [docs/images/](docs/images/) in the GitHub repository. 

## Technical Informations
* QT-Version 5.6.3
* Tested on Sailfish OS 5.0.0.62

## Roadmap
* Version 0.0.2 (planned):
  * Add optional authentication for local servers
  * Enhance supported widgets/element-types
  * Management of translations via CrowdIn
* Version 0.0.3 (planned):
  * Add support for remote access (via openHAB cloud)
  * Add App Notifications (via openHAB cloud)

## Localization

All language/regional translations are managed here [translations/*](translations/) in the GitHub repository. 
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
  ```
  <source>Save</source>
  <translation type="unfinished"></translation>
  ```
    with the correct translation for your language (remove "type="unfinished" and add the translation in between the <translation> tags). For example, for german:
  ```
  <source>Save</source>
  <translation>Speichern</translation>
  ```
Thanks for your consideration and contribution!

## Setting up development environment

If you want to contribute to Sailfish OS application we are here to help you to set up development environment. openHAB client for Sailfish OS is developed using Sailfish IDE.

- Download and install [Sailfish IDE](https://docs.sailfishos.org/Tools/Sailfish_SDK/Installation/)

You are ready to contribute!

## Trademark Disclaimer

Product names, logos, brands and other trademarks referred to within the openHAB website are the property of their respective trademark holders. These trademark holders are not affiliated with openHAB or our website. They do not sponsor or endorse our materials.

Sailfish OS and the Sailfish OS logo are trademarks of Jolla Group Ltd.