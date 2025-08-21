# Batterymonitord

**batterymonitord** is a small daemon that listens for changes in the battery/charging status of your MacBook and posts that information to a provided http endpoint. This useful for creating widgets that can display charge state of your battery without polling the command line.

## Installation/Usage

I've provided a script that will compile batterymtord, and load it as launchd service so the daemon starts on every login

```./install.sh {url of http sever}```

To build yourself: 

```swiftc batterymonitord/main.swift```

To fetch battery status as json:

```./batterymonitord -g```

To run the daemon:

```./batterymonitord -d {url of your http server}```


