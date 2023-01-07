# HLS Admin

This is a utility for managing a set of HLS streams.
The program provides a web frontend which allows the user to:

1. Select a supported video file for playback
2. Optionally select an external file to provide subtitles.
3. Select video, audio, and subtitle tracks from the chosen files.
4. Start & manage transcoding jobs which convert those files into
   various streams of HLS playlists & fragments.

## Requirements

- Elixir v1.12+ / Erlang OTP runtime to run the application
- `ffmpeg` and `ffprobe` (v4) in system `PATH` to handle media files

### Build Instructions

1. `git clone https://git.sr.ht/~hime/hls_admin`
2. `cd hls_admin`
3. `mix deps.get` and `mix deps.compile`
4. `iex -S mix phx.server`

Note: Please see `config/dev.exs` and look for the `config :hls_admin, :logins`
key. It is imperative that this is set correctly for your environment in order
to be able to use the software.

## Design

This server uses the `ffmpeg` command to run transcoding operations
which produce three HLS streams of varying quality levels. These
streams are "high" (~4Mbps), "mid" (~2Mbps), and "low" (~768Kbps).
They can be modified by adjusting the relevant bits of the FfmpegServer
process which resides at `lib/hls_admin/ffmpeg_server.ex`.

These streams can then be picked up by a suitable HLS-capable player,
for example the `video.js` project's HTML5 player. My [`stram`][stram-repo]
project is a ruby application that implements such a client. Esentially
your client will want to:

- Wait for the master playlist (`<playlist>/index.m3u8`) to become available.
- Add the streams in the master playlist to some sort of quality selector menu.
- Start playback as appropriate. (`stram` waits for several MPEG-TS segments to
  be available in the level-specific playlists to avoid buffering on startup.)

These ffmpeg streams are roughly setup as follows:

- Framerate is locked to 30fps, and keyframes are taken at a number of frames
  equal to the MPEG-TS segment size. This ensures that a client can start from
  *any* MPEG-TS segment without getting strange graphical artifacts. You will
  need to adjust these parameters if changing the HLS segment size and/or you
  need to display content w/ higher framerates.

- Subtitles are "burned in" using the `-vf=subtitles` filter. These parameters
  will need to be adjusted if you are trying to display content w/ "picture based"
  subtitles. (i.e: DVDs w/ a PGM stream.)

- The HLS segments are six seconds (180 frames) in length, and the ffmpeg process
  keeps ten such segments. So for each quality level there is approximately one
  minute of transcoded footage in-flight at any given time.

- We use the h.264 "main" profile and force the pixel format to yuv420p.
  This seems to provide the best compatibility w/ common user-agents.

## Web Application

**NOTE: This is standard boilerplate from the Phoenix Web Framework.**

To start your Phoenix server:

  * Install dependencies with `mix deps.get`
  * Create and migrate your database with `mix ecto.setup`
  * Install Node.js dependencies with `cd assets && npm install`
  * Start Phoenix endpoint with `mix phx.server`

Please review the files in the `config/` directory and set them appropriately
for your environment. In particular, to use the application, the :logins config
key must be present and contain a valid list of users & Argon2 hashes.

You can populate this config key using the mix task: `mix hls.hash <password>`.

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).
