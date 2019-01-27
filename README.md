# Installation


## Dependencies

* grab latest **Nim** from [GitHub](https://github.com/nim-lang/Nim) and follow **compiling** instructions
  * don't forget to add `Nim/bin` and `~/.nimble/bin` directory to your **PATH**
  * also build koch tools with `./koch tools` command
* mac users must install **Xcode** from *App Store* (after that install Xcode Command Line Tools with `xcode-select --install`) and [Brew](https://brew.sh/)
* install **sdl2**
  * linux users can use apt-get
  * mac users just type `brew install sdl2` command
* install **ffmpeg** or **libavtools**
  * linux users can use apt-get
  * mac users just type `brew install ffmpeg --with-libvorbis` command

## Building

1. Clone this repo
2. Install nimble dependencies
  `nimble install -dy`
3. Build and run (by default *prod* server will be used):
  `nake`

You also can use `nake help` to display possible options. For example you can choose which scene to load:
`nake -d:scene=WitchSlotView`

Or use [local server](https://github.com/OnsetGame/falconserver):
`nake -d:local`
