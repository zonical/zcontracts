
<h1 align="center">
ZContracts - Custom Contracker for SourceMod
</h1>


ZContracts is a plugin designed to emulate the Contracker progression system seen in Team Fortress 2. This project was heavily inspired by and started development during Creators.TF. The goal of this project is to provide an easy way for server developers to create a new gameplay experience for their players by completing as many Contracts as they can.

**DISCLAIMER:** This is still an alpha version of the plugin. Documentation on existing features will come once everything is finalised. Things are subject to change and more features will be added soon :tm:

## Installation & Building:
You will need the latest release of nosoop's stocksoup if you wish to build the plugin yourself. This is already included as a submodule inside the repository. When cloning the repository, make sure you grab the submodules as well: `git clone --recurse-submodules` and update the submodule when required: `git submodule update --remote --checkout`. Before compiling `zcontracts_main`, make sure there is a `scripting/zcontracts` folder with the required sub-plugins inside.

`zcontracts_events` and `zcontracts_tf2events` are separate plugins that handle calling Contracker events based on events called by the game and engine. They can be removed for custom implentations of events.

## Features:
- All Contract selection handled in-game. No third party website or API.
- Contracts can be grouped into directories (e.g `root/offense-contracts`).
- Objectives can have timer-based events (e.g "Kill three players in ten seconds.")
- Server operators can easily create and modify Contracts with a text editor.
- Plugin developers can easily create custom Contracker events with the provided Native functions (`CallContrackerEvent`).
- Two different types of Contract progress-collection: “Objective Based” and “Contract Based”:
  - "Objective Based" Contracts require all Objectives to be completed to finish a Contract.
  - "Contract Based" Contracts require getting a certain amount of points to finish a Contract.

## Questions, Issues, PR's.
Feel free to contact me at `ZoNiCaL#9740` on Discord if you have any questions.
I am open to pull-requests if there are any fixes or optimisations that I haven't made. If there are any bugs or feature requests, feel free to make an issue.
Please clearly explain what you're trying to accomplish with your threads and don't be a dick.
