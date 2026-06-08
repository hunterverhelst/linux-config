# linux-config
Collection of setup scripts and configs so I can quickly configure a new Linux environment the way I like it. Please don't judge.

## Install

Interactive install
```sh
curl -fsSL https://raw.githubusercontent.com/hunterverhelst/linux-config/refs/heads/main/setup.sh | sh
```

If you're not root and want to install packages non-interactively, cache sudo creds first

```sh
sudo -v
```

Install packages (non-interactive)
```sh
curl -fsSL https://raw.githubusercontent.com/hunterverhelst/linux-config/refs/heads/main/setup.sh | sh -s -- -install
```


