#include <libLoam/c++/ArgParse.h>
#include <libLoam/c++/ObColor.h>
#include <libNoodoo2/VisiDrome.h>
#include <libNoodoo2/VisiFeld.h>
#include <libNoodoo2/Scene.h>
#include <libNoodoo2/SimpleQuad.h>

using namespace oblong::loam;
using namespace oblong::basement;
using namespace oblong::noodoo2;
using namespace oblong::splotch;

// Demo program to draw a different color on each feld,
// with a commandline argument to change which color it starts with.
// Also creates a Scene and appends it to each VisiFeld, setting its
// Translation and Rotation to that of the first VisiFeld, and adding
// a SimpleQuad to it.

ObColor palette[3] = {
  {0.7, 0.3, 0.3},
  {0.3, 0.7, 0.3},
  {0.3, 0.3, 0.7}
};

ArgParse::apint demo_shift;

ObRetort Setup ()
{
  ObRetort error;

  // Create a new scene
  ObRef <Scene *> scene = new Scene ( SceneMode::Flat, error);
  if (error.IsError ())
    return error;

  // For each VisiFeld created by the Feld Protein,
  // set Background Color and Append Scene
  const int N = VisiFeld::NumAllVisiFelds ();
  for (int i = 0; i < N; ++i)
    {
      VisiFeld *vf = VisiFeld::NthOfAllVisiFelds (i);
      const size_t palette_size = sizeof (palette) / sizeof (*palette);
      vf->SetBackgroundColor (palette[(i + demo_shift) % palette_size]);

      // Append Scene toVisifelds
      vf->AppendScene (~scene);

      // Set Scene RootShowyThing to location of first visifeld
      if (i==0)
      {
        scene -> RootShowyThing () -> TranslateLikeFeld (vf);
        scene -> RootShowyThing () -> RotateLikeFeld (vf);
      }
    }

  // Now you can add ShowyThings to the Scenes RootShowyThing
  // Here, we just create a SimpleQuad
  ObRef <SimpleQuad *> simplequad = new SimpleQuad (error);
  simplequad -> SetBackingColor (ObColor (1.0,0.0,0.0));
  simplequad -> SetSize (100,100);

  scene -> RootShowyThing () -> AppendChild (~simplequad);

  return OB_OK;
}

int main (int argc, char **argv)
{
  ArgParse ap (argc, argv);
  ap.ArgInt ("demo-shift", "\aNumber of positions to shift palette",
             &demo_shift);
  ap.EasyFinish (0, ArgParse::UNLIMITED);

  // Pass any leftover commandline arguments to the VisiDrome constructor.
  // It will treat them as protein file names and deposit them into 'drome-pool',
  // which is like g-speak's live configuration inbox.
  // See e.g. "Setting up Screen and Feld Proteins" in
  // https://platform.oblong.com/learning/g-speak/recipes/

  VisiDrome *instance = new VisiDrome ("noodoo2test2", ap.Leftovers ());

  Setup ();
  instance->Respire ();
  instance->Delete ();

  return 0;
}
