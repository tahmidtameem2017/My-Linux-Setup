#!/usr/bin/env python3
import gi

gi.require_version("Playerctl", "2.0")
from gi.repository import Playerctl, GLib
from gi.repository.Playerctl import Player
import argparse
import logging
import sys
import signal
import gi
import json
import os
from typing import List

logger = logging.getLogger(__name__)


def signal_handler(sig, frame):
    logger.info("Received signal to stop, exiting")
    sys.stdout.write("\n")
    sys.stdout.flush()
    sys.exit(0)


def format_time(seconds):
    m = int(seconds // 60)
    s = int(seconds % 60)
    return f"{m}:{s:02d}"


class PlayerManager:
    def __init__(self, selected_player=None, excluded_player=[]):
        self.manager = Playerctl.PlayerManager()
        self.loop = GLib.MainLoop()
        self.manager.connect(
            "name-appeared", lambda *args: self.on_player_appeared(*args)
        )
        self.manager.connect(
            "player-vanished", lambda *args: self.on_player_vanished(*args)
        )

        signal.signal(signal.SIGINT, signal_handler)
        signal.signal(signal.SIGTERM, signal_handler)
        signal.signal(signal.SIGPIPE, signal.SIG_DFL)
        self.selected_player = selected_player
        self.excluded_player = excluded_player.split(",") if excluded_player else []

        self.init_players()

    def init_players(self):
        for player in self.manager.props.player_names:
            if player.name in self.excluded_player:
                continue
            if self.selected_player is not None and self.selected_player != player.name:
                logger.debug(f"{player.name} is not the filtered player, skipping it")
                continue
            self.init_player(player)

    def run(self):
        logger.info("Starting main loop")
        self.loop.run()

    def init_player(self, player):
        logger.info(f"Initialize new player: {player.name}")
        player = Playerctl.Player.new_from_name(player)
        player.connect("playback-status", self.on_playback_status_changed, None)
        player.connect("metadata", self.on_metadata_changed, None)
        self.manager.manage_player(player)
        self.on_metadata_changed(player, player.props.metadata)

    def get_players(self) -> List[Player]:
        return self.manager.props.players

    def get_player_time(self, player):
        try:
            position = player.get_position()
        except Exception:
            position = 0
        metadata = player.props.metadata
        if metadata and "mpris:length" in metadata:
            length = metadata["mpris:length"] / 1_000_000
        else:
            length = 0
        position_sec = position / 1_000_000
        return position_sec, length

    def write_output(self, text, player, status):
        logger.debug(f"Writing output: {text}")

        player_name = player.props.player_name
        artist = player.get_artist() or ""
        title = player.get_title() or ""
        album = ""
        if player.props.metadata and "xesam:album" in player.props.metadata:
            album = player.props.metadata["xesam:album"] or ""

        tooltip_lines = []
        status_icon = "" if status == "Playing" else ""
        tooltip_lines.append(f"{status_icon}  {player_name}")

        if title:
            tooltip_lines.append(f"  {title}")
        if artist:
            tooltip_lines.append(f"  {artist}")
        if album:
            tooltip_lines.append(f"  {album}")

        pos, length = self.get_player_time(player)
        if length > 0:
            tooltip_lines.append(f"  {format_time(pos)} / {format_time(length)}")

        output = {
            "text": text,
            "class": [f"custom-{player_name}", status.lower()],
            "alt": player_name,
            "tooltip": "\n".join(tooltip_lines),
        }

        sys.stdout.write(json.dumps(output) + "\n")
        sys.stdout.flush()

    def clear_output(self):
        sys.stdout.write("\n")
        sys.stdout.flush()

    def on_playback_status_changed(self, player, status, _=None):
        logger.debug(
            f"Playback status changed for player {player.props.player_name}: {status}"
        )
        self.on_metadata_changed(player, player.props.metadata)

    def get_first_playing_player(self):
        players = self.get_players()
        logger.debug(f"Getting first playing player from {len(players)} players")
        if len(players) > 0:
            for player in players[::-1]:
                if player.props.status == "Playing":
                    return player
            return players[0]
        else:
            logger.debug("No players found")
            return None

    def show_most_important_player(self):
        logger.debug("Showing most important player")
        current_player = self.get_first_playing_player()
        if current_player is not None:
            self.on_metadata_changed(current_player, current_player.props.metadata)
        else:
            self.clear_output()

    def on_metadata_changed(self, player, metadata, _=None):
        logger.debug(f"Metadata changed for player {player.props.player_name}")
        player_name = player.props.player_name
        title = player.get_title()
        if title:
            title = title.replace("&", "&amp;")

        is_ad = (
            player_name == "spotify"
            and "mpris:trackid" in metadata.keys()
            and ":ad:" in player.props.metadata["mpris:trackid"]
        )

        if player.props.status == "Playing" and not is_ad:
            text = ""
        elif player.props.status == "Paused":
            text = ""
        else:
            text = ""

        current_playing = self.get_first_playing_player()
        if (
            current_playing is None
            or current_playing.props.player_name == player.props.player_name
        ):
            self.write_output(text, player, player.props.status)
        else:
            logger.debug(
                f"Other player {current_playing.props.player_name} is playing, skipping"
            )

    def on_player_appeared(self, _, player):
        logger.info(f"Player has appeared: {player.name}")
        if player.name in self.excluded_player:
            logger.debug(
                "New player appeared, but it's in exclude player list, skipping"
            )
            return
        if player is not None and (
            self.selected_player is None or player.name == self.selected_player
        ):
            self.init_player(player)
        else:
            logger.debug(
                "New player appeared, but it's not the selected player, skipping"
            )

    def on_player_vanished(self, _, player):
        logger.info(f"Player {player.props.player_name} has vanished")
        self.show_most_important_player()


def parse_arguments():
    parser = argparse.ArgumentParser()

    parser.add_argument("-v", "--verbose", action="count", default=0)

    parser.add_argument("-x", "--exclude", "- Comma-separated list of excluded player")

    parser.add_argument("--player")

    parser.add_argument("--enable-logging", action="store_true")

    return parser.parse_args()


def main():
    arguments = parse_arguments()

    if arguments.enable_logging:
        logfile = os.path.join(
            os.path.dirname(os.path.realpath(__file__)), "media-player.log"
        )
        logging.basicConfig(
            filename=logfile,
            level=logging.DEBUG,
            format="%(asctime)s %(name)s %(levelname)s:%(lineno)d %(message)s",
        )

    logger.setLevel(max((3 - arguments.verbose) * 10, 0))

    logger.info("Creating player manager")
    if arguments.player:
        logger.info(f"Filtering for player: {arguments.player}")
    if arguments.exclude:
        logger.info(f"Exclude player {arguments.exclude}")

    player = PlayerManager(arguments.player, arguments.exclude)
    player.run()


if __name__ == "__main__":
    main()
