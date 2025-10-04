import sys
import rpc
import time
import json
import os
import ast
from PIL import Image, ImageGrab
import win32gui
import win32api
import win32con
import logging

# localisation variables. Change them for your preferences.
inMainMenu = "In main menu"
# these are internal use variables, don't touch them, unless you know what you're doing.
logging.basicConfig(filename='log.txt', filemode='w', encoding='utf-8', level=logging.INFO)
decoded = ''
DEBUG_SAVE_STRIP = False
wow_hwnd = None
rpc_obj = None
timePlayed = None
dir_path = os.path.dirname(os.path.realpath(__file__))
f = open(dir_path + '/zones.txt')
zones = ast.literal_eval(f.read())
print("The script is running!\n"
      "Now you can minimize the window and play WoW.\n"
      "The script will terminate automatically when you exit the game.\n"
      "Check log.txt if you need detailed information.")


def callback(hwnd, extra):
    global wow_hwnd
    if (win32gui.GetWindowText(hwnd) == 'Ascension'):
        wow_hwnd = hwnd


def save_debug_image(rect, offsetX, offsetY, height=50, iter_tag=0):
    """
    Grabs a taller slice of the same top-left band we read for pixels,
    and saves it to the script directory for inspection.
    """
    # Same left/right/offset logic as getImage, but with a taller height.
    new_rect = (rect[0] + offsetX, rect[1] + offsetY, rect[2], rect[1] + offsetY + height)
    try:
        im50 = ImageGrab.grab(new_rect, all_screens=True)
        out_path = os.path.join(dir_path, f"debug_strip_{iter_tag}_{int(time.time())}.png")
        im50.save(out_path)
        logging.info("Saved debug image: %s", out_path)
    except Exception as exc:
        logging.error("Failed to save debug image: %s", exc)


def getImage(rect, offsetX, offsetY, iter, strip_h=2, bleed_guard_dx=1, bleed_guard_dy=1):
    """
    Grab a top strip with extra guard margins to avoid edge blending and index errors.
    Returns an image of exact height `strip_h`, whose (0,0) is already shifted by the guard.
    """
    # Build a bbox with extra vertical margin so we can crop down safely.
    left = rect[0] + offsetX
    top = rect[1] + offsetY
    right = rect[2]  # full window right edge
    lower = top + strip_h + bleed_guard_dy  # add room for guard

    # Clamp to window bottom just in case
    lower = min(lower, rect[3])
    if right <= left or lower <= top + bleed_guard_dy:
        logging.error("Invalid bbox after guards: %s", (left, top, right, lower))
        return False

    new_rect = (left, top, right, lower)
    logging.debug("Window rectangle (with guard): %s; Iteration %s", str(new_rect), iter)

    try:
        im_full = ImageGrab.grab(new_rect, all_screens=True)

        # Now crop away the guard so returned image has height=strip_h and starts at safe origin.
        crop_left = bleed_guard_dx
        crop_top = bleed_guard_dy
        crop_right = im_full.width  # keep full width (minus dx)
        crop_bottom = bleed_guard_dy + strip_h

        # Clamp crop to avoid index errors if window is tiny/edge cases.
        crop_left = max(0, min(crop_left, im_full.width - 1))
        crop_top = max(0, min(crop_top, im_full.height - 1))
        crop_right = max(crop_left + 1, min(crop_right, im_full.width))
        crop_bottom = max(crop_top + 1, min(crop_bottom, im_full.height))

        im = im_full.crop((crop_left, crop_top, crop_right, crop_bottom))

        # Optional sanity check sample that can’t go OOB:
        logging.debug("Safe origin pixel: %s", im.getpixel((0, 0)))

        # check (0,0) for the sentinel color, keep doing that:
        if im.getpixel((0, 0)) == (36, 36, 36):
            logging.debug("AbsPosFound (after guard+crop)")
            return im

        # Borderless/windowed fallback stays the same:
        if iter == 0:
            height = (win32api.GetSystemMetrics(win32con.SM_CYCAPTION) + win32api.GetSystemMetrics(win32con.SM_CYBORDER) * 4 + win32api.GetSystemMetrics(win32con.SM_CYEDGE) * 2)
            logging.debug("Window border height: %s", height)
            return getImage(rect, offsetX, height, 1, strip_h, bleed_guard_dx, bleed_guard_dy)
        elif iter == 1:
            return getImage(rect, 8, offsetY, 2, strip_h, bleed_guard_dx, bleed_guard_dy)

        return False

    except Image.DecompressionBombError:
        logging.error('DecompressionBombError')
        return False


def read_squares(hwnd):
    global decoded
    rect = win32gui.GetWindowRect(hwnd)
    im = getImage(rect, 0, 0, 0)
    if im is False:
        return 1


    # Check if there's a message at the top left corner.
    # If there's none, then we're either in main menu or addon is not working.
    # Sometimes addon moves 1 px to the right, so we check if that is the case.
    offset = 0
    if im.getpixel((1, 0)) == (0, 0, 0):
        logging.debug("Pixels are 1x1 starting at position 0")
        # Second pixel also can be duplicated due to resizing.
    elif im.getpixel((1, 0)) == (36, 36, 36) and im.getpixel((2, 0)) in ((0, 0, 0), (36, 36, 36)):
        p2 = im.getpixel((2, 0))
        if p2 == (0, 0, 0):
            logging.debug("Pixels start at position 1")
        else:  # (36, 36, 36)
            logging.debug("Pixels are more than 1x1 (duplicated due to resizing)")
        offset += 1
    else:
        logging.info("Could not find pixel array. You're either in main menu or addon is not working")
        return 1

    read = []
    skipped_pixels_counter = 0
    for pixel_idx in range(offset, int(im.width)):
        current_pixel_colors = im.getpixel((pixel_idx, 0))
        if current_pixel_colors[0] == 255 or current_pixel_colors[1] == 255 or current_pixel_colors[2] == 255:
            break

        # When in-game width is set to 3 or more, we will skip two "bad" pixels.
        # First next pixel is 100% bad, second is 50/50, third one is 100% good, so we will get its color
        if 0 < skipped_pixels_counter < 3:
            skipped_pixels_counter += 1
            continue

        next_pixel_colors = im.getpixel((pixel_idx + 1, 0))
        # If we've found difference in pixels, there's a good chance these are
        # "smoothed" pixels and they can't be decoded as they don't represent any data
        if current_pixel_colors != next_pixel_colors:
            # ...so we will save the latest good pixel and skip the next two
            read += [color for color in current_pixel_colors]
            skipped_pixels_counter = 1

    try:
        logging.debug('Trying to decode pixels: %s' % ", ".join(map(str, read)))
        decoded = bytes(read).decode('utf-8').rstrip('\0')
    except Exception as exc:
        logging.error('Error decoding the pixels: %s.' % exc)
        print('Something is overlapping information pixels, or the game is running in full-screen. '
              'If it so, change the mode to windowed or borderless.')
        return 0
    parts = decoded.replace('$$$', '').split('|')

    # sanity check
    if (not decoded.endswith('$$$') or not decoded.startswith('$$$')):
        return 0

    return parts


def connect_to_discord():
    global rpc_obj
    if not rpc_obj:
        logging.info('Not connected to Discord, connecting...')
        while True:
            try:
                rpc_obj = (rpc.DiscordIpcClient
                           .for_platform("827272838771507210"))
            except Exception as exc:
                logging.warning("I couldn't connect to Discord (%s). It's "
                                'probably not running. I will try again in 5 '
                                'sec.' % str(exc))
                time.sleep(5)
                pass
            else:
                break


def update_activity(activity):
    global rpc_obj
    try:
        rpc_obj.set_activity(activity)
    except Exception as exc:
        logging.warning('Looks like the connection to Discord was broken (%s). '
                        'I will try to connect again in 5 sec.' % str(exc))
        rpc_obj = None


while True:
    wow_hwnd = None
    win32gui.EnumWindows(callback, None)

    if win32gui.GetForegroundWindow() == wow_hwnd:
        lines = read_squares(wow_hwnd)

        if not lines:  # Something went wrong
            time.sleep(5)
            continue

        # We know that we're either in main menu or addon is not working
        elif lines == 1:
            connect_to_discord()
            if timePlayed is None:
                timePlayed = {'start': round(time.time())}
            activity = {
                'details': inMainMenu,
                'timestamps': timePlayed,
                'assets': {
                    'large_image': "wow-icon"
                }
            }
            logging.info("Setting activity: %s" % inMainMenu)
            update_activity(activity)
            time.sleep(3)
            continue
        else:
            zoneName, playerLevel, playerName, realmName, playerInfo, engClass, playerState, mapID = lines
            connect_to_discord()

            logging.info('Setting new activity: %s - %s - %s- %s - %s - %s - %s - %s' % (
                zoneName, playerLevel, playerName, realmName, playerInfo, engClass, playerState, mapID))

            if timePlayed is None:
                timePlayed = {'sta  rt': round(time.time())}
            if mapID in zones.keys():
                zone = zones[str(mapID)]
            else:
                zone = "wow-icon"
                logging.warning("The zone is not in the list: %s [ID: %s]" % (zoneName, mapID))
            activity = {
                'details': "Ascension (%s)" % realmName,
                'details_url': "https://ascension.gg/en",
                'state': "%s [Lvl %s]" % (playerName, playerLevel),
                'assets': {
                    'large_image': zone,
                    'large_text': zoneName,
                    'large_url': "https://ascension.gg/en",
                    'small_image': engClass.lower(),
                    'small_text': playerInfo
                },
                'timestamps': timePlayed
            }
            update_activity(activity)

    elif not wow_hwnd and rpc_obj:
        logging.info('WoW no longer exists, terminating...')
        rpc_obj.close()
        sys.exit()
    time.sleep(5)
