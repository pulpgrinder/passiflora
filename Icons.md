
The `src/icons` folder contains two large template icons, `roundicon.png` and `squareicon.png`. You can change these to whatever PNG images you like. They should be pretty big — around 1,000 pixels square. More is better! The `squareicon.png` file should be square (duh!), while the `roundicon.png` should be a square image with an inscribed round image on a transparent background (I realize that may sound a little confusing... look at the supplied `roundicon.png` if you need clarification).

All of the zillions of other icons needed by the the various targets are generated from these.

Once you've updated the base icons, run:

`make icons` (macOS and Linux)

or

`.\build icons` (Windows)

to generate a new icon set.

Note that these may need some manual tweaking for legibility, particularly at the smaller sizes, but it's still a substantial time savings over producing them all manually. Note that icons are *not* regenerated automatically during a normal build (not even after `make clean`). This is so any hand-tuned versions you've created won't be overwritten. If you *do* want to wipe out all existing icons and start over, run `make icons` or `.\build icons` again.