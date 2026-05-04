#!/bin/bash

ASEPRITE_PATH="Aseprite"
SKILL_SLOTS_FILE="../SkillTree.aseprite"
BANNERRS_FILE="../Banners.aseprite"
BUTTONS_FILE="../Buttons.aseprite"
FACELESS_BUTTONS_PATH="../FacelessButtons.aseprite"
DIRECTIONAL_BUTTONS_PATH="../DirectionalButtons.aseprite"
THUMBSTICKS_PATH="../Thumbsticks.aseprite"
SYSTEM_BUTTONS_PATH="../SystemButtons.aseprite"
SHOULDER_BUTTONS_PATH="../ShoulderButtons.aseprite"
TOUCHPAD_PATH="../Touchpad.aseprite"
ICONS_PATH="../Icons.aseprite"
INDICATORS_PATH="../Indicators.aseprite"
CONTROLLER_PATH="../Controller.aseprite"
CONTROLLER_DIAGRAMS_PATH="../ControllerDiagrams.aseprite"
SPLASH_PATH="../Splash.aseprite"
TV_PATH="../TV.aseprite"
LOGOS_PATH="../Logos.aseprite"
EXPORT_FOLDER_TAG_COMBINATIONS="./ExportFolderTagCombinations.lua"
EXPORT_SLICES="./ExportSlices.lua"
EXPORT_SLICE_TAGS="./ExportSliceTags.lua"
EXPORT_LAYER_SLICES="./ExportLayerSlices.lua"
EXPORT_SHEET="./ExportSheet.lua"
EXPORT_LAYERS="./ExportLayers.lua"
EXPORT_TAGS="./ExportTags.lua"
SPRITES_FOLDER="../../Sprites/"
PARAMS="--script-param sprites-folder=$SPRITES_FOLDER"

display_menu() {
  echo "Please choose an option:"
  echo "1. Banners"
  echo "2. Buttons"
  echo "3. Skill Slots"
  echo "3. All"
  echo "4. Exit"
}

export_skill_slots() {
  echo "Exporting Skill Slots"
  "$ASEPRITE_PATH" -b "$SKILL_SLOTS_FILE" $PARAMS --script "$EXPORT_LAYERS"
  "$ASEPRITE_PATH" -b "$SKILL_SLOTS_FILE" $PARAMS --script "$EXPORT_LAYER_SLICES"
}

export_banners() {
  echo "Exporting Banners"
  "$ASEPRITE_PATH" -b "$BANNERRS_FILE" $PARAMS --script "$EXPORT_SHEET"
  "$ASEPRITE_PATH" -b "$BANNERRS_FILE" $PARAMS --script "$EXPORT_SLICES"
}

export_buttons() {
  echo "Exporting Buttons"
  "$ASEPRITE_PATH" -b "$BUTTONS_FILE" $PARAMS --script "$EXPORT_SLICE_TAGS"
}

export_thumbsticks() {
  echo "Exporting Thumbsticks"
  "$ASEPRITE_PATH" -b "$THUMBSTICKS_PATH" $PARAMS --script "$EXPORT_FOLDER_TAG_COMBINATIONS"
}

export_system_buttons() {
  echo "Exporting System Buttons"
  "$ASEPRITE_PATH" -b "$SYSTEM_BUTTONS_PATH" $PARAMS --script "$EXPORT_FOLDER_TAG_COMBINATIONS"
}

export_shoulder_buttons() {
  echo "Exporting Shoulder Buttons"
  "$ASEPRITE_PATH" -b "$SHOULDER_BUTTONS_PATH" $PARAMS --script "$EXPORT_FOLDER_TAG_COMBINATIONS"
}

export_touchpad() {
  echo "Exporting Touchpad"
  "$ASEPRITE_PATH" -b "$TOUCHPAD_PATH" $PARAMS --script "$EXPORT_FOLDER_TAG_COMBINATIONS"
}

export_controller() {
  echo "Exporting Controller"
  "$ASEPRITE_PATH" -b "$CONTROLLER_PATH" $PARAMS --script "$EXPORT_SLICES"
}

export_controller_diagrams() {
  echo "Exporting Controller Diagrams"
  "$ASEPRITE_PATH" -b "$CONTROLLER_DIAGRAMS_PATH" $PARAMS --script-param trim-cels="true" --script "$EXPORT_FOLDER_TAG_COMBINATIONS"
}

export_indicators() {
  echo "Exporting Indicators"
  "$ASEPRITE_PATH" -b "$INDICATORS_PATH" $PARAMS --script "$EXPORT_FOLDER_TAG_COMBINATIONS"
}

export_icons() {
  echo "Exporting Icons"
  "$ASEPRITE_PATH" -b "$ICONS_PATH" $PARAMS --script "$EXPORT_SLICES"
  "$ASEPRITE_PATH" -b "$ICONS_PATH" $PARAMS --script "$EXPORT_SHEET"
}

export_splash_screen() {
  echo "Exporting Logos"
  "$ASEPRITE_PATH" -b "$LOGOS_PATH" $PARAMS --script "$EXPORT_SLICES"
  "$ASEPRITE_PATH" -b "$LOGOS_PATH" $PARAMS --script "$EXPORT_SHEET"
}

export_logos() {
  echo "Exporting Splash Screen"
  "$ASEPRITE_PATH" -b "$SPLASH_PATH" $PARAMS --script-param trim="false" --script "$EXPORT_FOLDER_TAG_COMBINATIONS"
}

export_tv() {
  echo "Exporting TV"
  "$ASEPRITE_PATH" -b "$TV_PATH" $PARAMS --script "$EXPORT_TAGS"
}

while true; do
  display_menu
  read -p "Enter your choice [1-13]: " choice

  case $choice in
  1)
    export_banners
    ;;
  2)
    export_buttons
    ;;
  3)
    export_skill_slots
    ;;
  4)
    export_thumbsticks
    ;;
  5)
    export_system_buttons
    ;;
  6)
    export_shoulder_buttons
    ;;
  7)
    export_touchpad
    ;;
  8)
    export_controller
    export_controller_diagrams
    ;;
  9)
    export_indicators
    ;;
  10)
    export_icons
    ;;
  11)
    export_splash_screen
    export_logos
    export_tv
    ;;
  12)
    echo "Exporting All"
    
    ;;
  13)
    echo "Exiting..."
    break
    ;;
  *)
    echo "Invalid option. Please try again."
    ;;
  esac

  echo ""
done
