defmodule Mix.Tasks.Hls.Hash do
  use Mix.Task


  @shortdoc "Create a hashed password for inclusion in the :logins config key."
  def run(args) do
    case Enum.count(args) do
      1 -> IO.puts Argon2.hash_pwd_salt(Enum.at(args,0))
      _argn -> IO.puts "Please supply a password to be hashed."
    end
  end
end
