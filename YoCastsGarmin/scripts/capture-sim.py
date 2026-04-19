"""Capture a screenshot of the CIQ Simulator window using the Win32 PrintWindow API.
Works even if the simulator is off-screen or on another monitor.

Usage: python scripts/capture-sim.py [output_path]
Default output: screenshots/sim-capture.png
"""
import sys
import ctypes
from PIL import Image
import win32gui
import win32ui

def find_sim_hwnd():
    results = []
    def callback(hwnd, _):
        if win32gui.IsWindowVisible(hwnd):
            title = win32gui.GetWindowText(hwnd)
            if 'CIQ Simulator' in title:
                results.append((hwnd, title))
        return True
    win32gui.EnumWindows(callback, None)
    return results

def capture(output_path):
    windows = find_sim_hwnd()
    if not windows:
        print('Simulator not found')
        return False

    hwnd, title = windows[0]
    rect = win32gui.GetWindowRect(hwnd)
    w = rect[2] - rect[0]
    h = rect[3] - rect[1]

    hwndDC = win32gui.GetWindowDC(hwnd)
    mfcDC = win32ui.CreateDCFromHandle(hwndDC)
    saveDC = mfcDC.CreateCompatibleDC()
    saveBitMap = win32ui.CreateBitmap()
    saveBitMap.CreateCompatibleBitmap(mfcDC, w, h)
    saveDC.SelectObject(saveBitMap)

    # PW_RENDERFULLCONTENT = 3
    ctypes.windll.user32.PrintWindow(hwnd, saveDC.GetSafeHdc(), 3)

    bmpinfo = saveBitMap.GetInfo()
    bmpstr = saveBitMap.GetBitmapBits(True)
    img = Image.frombuffer('RGB', (bmpinfo['bmWidth'], bmpinfo['bmHeight']),
                           bmpstr, 'raw', 'BGRX', 0, 1)
    img.save(output_path)
    print(f'Captured {img.size[0]}x{img.size[1]} -> {output_path}')

    win32gui.DeleteObject(saveBitMap.GetHandle())
    saveDC.DeleteDC()
    mfcDC.DeleteDC()
    win32gui.ReleaseDC(hwnd, hwndDC)
    return True

if __name__ == '__main__':
    out = sys.argv[1] if len(sys.argv) > 1 else 'screenshots/sim-capture.png'
    capture(out)
