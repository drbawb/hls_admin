# HLS Admin

This is a utility for managing a set of HLS streams.
The program provides a web frontend which allows the user to:

1. Select a supported video file for playback
2. Optionally select an external file to provide subtitles.
3. Select video, audio, and subtitle tracks from the chosen files.
4. Start & manage transcoding jobs which convert those files into
   various streams of HLS playlists & fragments.

## Requirements

- Elixir v1.5+ / Erlang OTP runtime to run the application
- NodeJS to compile static assets for the web frontend
- `ffmpeg` and `ffprobe` (v4) in system `PATH` to handle media files

## Web Application

**NOTE: This is standard boilerplate from the Phoenix Web Framework.**

To start your Phoenix server:

  * Install dependencies with `mix deps.get`
  * Create and migrate your database with `mix ecto.setup`
  * Install Node.js dependencies with `cd assets && npm install`
  * Start Phoenix endpoint with `mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).
