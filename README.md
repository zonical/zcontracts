
<h1 align="center">
ZContracts - Custom Contracker for SourceMod
</h1>

ZContracts is a free, no BS solution for sever operators who wish to have an experience similar to the Contracker progression system seen in Team Fortress 2. This project was heavily inspired by and started development during Creators.TF. The goal of this project is to provide an easy way for server developers to create a new gameplay experience for their players by completing as many Contracts as they can.

The plugin is officially supported for Team Fortress 2. Work has been started for CSGO but with the imminent release of CS2 and the uncertainty of SourceMod working on Source 2, I'm putting my focus towards supporting TF2.

**DISCLAIMER:** This is a beta version! Documentation on existing features will be incomplete. Things are subject to change and there might be breaking changes!

## Installation

**Requirements:**
- SourceMod 1.11+ (tested on 1.12.0.6967)
- If running on TF2: [tf_econ_data by nosoop](https://github.com/nosoop/SM-TFEconData/tree/master)
- MySQL 5.6+ database

**Instructions:**
1) Extract the contents of `/addons/sourcemod` to your SourceMod installation.
2) Depending on the game, install the required plugins (e.g for TF2, install tf_econ_data).
3) Update `databases.cfg` to include an entry for `"zcontracts"`. An example can be found [here](https://github.com/zonical/zcontracts/blob/master/addons/sourcemod/configs/databases_example.cfg).
4) Import the [SQL structure](https://github.com/zonical/zcontracts/blob/master/database/zcontracts.sql) into your database. 
5) Turn on your server. There should be console output that starts with `[ZContracts]` when SourceMod is initalised. It will report how many Contracts are loaded and if a connection is established with the database.
6) Double check that all the version numbers of all ZContracts plugins are synchronized. You can check this by typing `sm plugins list` in your server console. If the version are not synchronized, update your ZContracts install immediately.

## Building
You will need the latest release of nosoop's stocksoup if you wish to build the plugin yourself. This is already included as a submodule inside the repository. When cloning the repository, make sure you grab the submodules as well: `git clone --recurse-submodules` and update the submodule when required: `git submodule update --remote --checkout`. Before compiling `zcontracts_main`, make sure there is a `scripting/zcontracts` folder with the required sub-plugins inside.

If you are building `zcontracts_tf2`, you will need the latest release of [tf_econ_data by nosoop](https://github.com/nosoop/SM-TFEconData/tree/master). I have included the .inc file in the repositiory.

If you make any edits to any of the enum structs, make sure you recompile all plugins that use ZContracts.

## Features
- All Contract selection handled in-game. No third party website or API.
- Contracts can be grouped into directories (e.g `root/offense-contracts`).
- Objectives can have timer-based events (e.g "Kill three players in ten seconds.")
- Server operators can easily create and modify Contracts with a text editor.
- Plugin developers can easily create custom Contracker events with the provided Native functions.
- Two different types of Contract progress-collection: “Objective Progress” and “Contract Progress”:
  - "Objective Based" Contracts require all Objectives to be completed to finish a Contract.
  - "Contract Based" Contracts require getting a certain amount of points to finish a Contract.
- Lots of customisation (e.g Contracts can be repeated infinitely), all controllable with ConVars.

## Usage
This plugin, like any other SourceMod plugin, falls under the [SourceMod License](https://www.sourcemod.net/license.php) (specifically GPLv3). You are free to use this plugin on your server and modify the plugin source code to suit your own needs. I would appreciate a small credit for creating the plugin but it's not a requirement. This plugin will always be open sourced and free. The sample Contracts provided in this repositiory are free to be used, modified, or deleted.

## Questions, Issues, PR's
Feel free to contact me at `ZoNiCaL#9740` on Discord if you have any questions.
I am open to pull-requests if there are any fixes or optimisations that I haven't made. If there are any bugs or feature requests, feel free to make an issue.
Please clearly explain what you're trying to accomplish with your threads and don't be a dick.

# Special Thanks
- Creators.TF: for being the reason this project was created and for helping develop my SourceMod abilities.
- nosoop: Small snippits of Contract schema-loading code was borrowed from Custom Weapons X while I was creating a custom version of the plugin for Creators.TF
- HiGPS & BalanceMod: For reviving this project after the closure of Creators.TF.
