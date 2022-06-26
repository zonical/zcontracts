# ZContracts - A custom Contract system for SourceMod

ZContracts is a plugin inspired by the Creators.TF Contracker system, which itself was inspired from TF2 Contracker. Its goal is to provide an easy way for server developers to create a new gameplay experience for their players by completing as many Contracts as they can.

**DISCLAIMER:** This is still an alpha version of the plugin. Documentation on existing features will come once everything is finalised. Things are subject to change and more features will be added soon :tm:

## Installation & Building:
Included with release downloads is the source-code, example contracts and the main plugin: `zcontracts_main.smx`. Drag the `zcontracts` folder into the `sourcemods/configs/` folder, then drag the plugin into the `sourcemods/plugins/` folder and type `sm plugins load zcontracts_main` into the console.

You will need the latest release of nosoop's stocksoup if you wish to build the plugin yourself. This is already included as a submodule inside the repository. When cloning the repository, make sure you grab the submodules as well: `git clone --recurse-submodules` and update the submodule when required: `git submodule update --remote --checkout`. Before compiling `zcontracts_main`, make sure there is a `scripting/zcontracts` folder with the required sub-plugins inside.

## Features:
- Server operators can easily create and modify Contracts with a text editor.
- Contracts can be grouped into directories (e.g `root/offense-contracts`).
- All menu interactions and Contract selection dialogue are handled in-game.
- Two different types of Contract progress-collection: “Objective Based” and “Contract Based”:

| Feature | Objective Based | Contract Based |
| :---: | :---: | :---: |
| Progress | Each objective has its own progress bar (defined per objective) | Each objective has its own progress bar OR can be completed infinitely (defined per objective), One central progress bar (defined per contract) |
| Completion | Each objective must be completed to finish the Contract. | The central progress bar must be completed to finish the Contract. |
| In-Game chat example | `[ZC] You have selected the contract: "Example Contract - Kills (Type 1)". To complete it, finish all the objectives.` | `[ZC] You have selected the contract: "Example Contract - Kills (Type 2)". To complete it, get 100CP.` |

- Objectives can have timer-based events.
- Server operators can create custom Contracker events with the provided Native functions (`CallContrackerEvent`).
- Up to eight objectives per Contract.

## Commands:
- `!c`, `!contracts`: Opens up a menu to select a Contract.

![image](https://user-images.githubusercontent.com/30227729/175792795-3ed16f37-15ad-4820-a574-871ade94ab31.png)

- `!setcontract`: Admin command that sets the Contract of the player with the Contract's UUID as the first argument.
- `!reloadcontracts`: Server command that reloads the Contract schema.

## Questions, Issues, PR's.
Feel free to contact me at `ZoNiCaL#9740` on Discord if you have any questions.
I am open to pull-requests if there are any fixes or optimisations that I haven't made. If there are any bugs or feature requests, feel free to make an issue.
Please clearly explain what you're trying to accomplish with your threads and don't be a dick.
