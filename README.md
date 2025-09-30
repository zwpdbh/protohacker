# Protohacker

For solving problems from [Protohackers](https://protohackers.com/problems)


## Install asdf 

The easiest way to install asdf is from go: download one of go binary from `https://go.dev/dl/`.

```sh 
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf go1.24.4.linux-amd64.tar.gz
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.profile
echo 'export GOPATH=$HOME/go' >> ~/.profile
source ~/.profile
go version
go install github.com/asdf-vm/asdf/cmd/asdf@v0.17.0

# expose go bin path to terminal
echo 'export PATH="$PATH:$HOME/go/bin"' >> ~/.bashrc
# expose asdf installed code (add to bashrc to make it permanent)
export PATH="$HOME/.asdf/shims:$PATH"
source ~/.bashrc
```


## Install Elixir and Erlang 

```sh 
asdf --version
asdf plugin add erlang https://github.com/asdf-vm/asdf-erlang.git
asdf plugin add elixir https://github.com/asdf-vm/asdf-elixir.git

asdf install erlang 27.2
asdf install elixir latest

# expose asdf installed code (add to bashrc to make it permanent)
export PATH="$HOME/.asdf/shims:$PATH"

asdf list erlang 
asdf list elixir 

asdf set erlang 27.2
asdf set elixir 1.18.4-otp-27

# check current erlang and elixir setting
erl -eval 'erlang:display(erlang:system_info(otp_release)), halt().'
elixir -v
```
