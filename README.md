# StorySlider

It's a super awesome tool for helping debug interactive fiction! You give it a YAML file that describes your fiction, and it traverses every single potential pathway through the story nodes, taking into account flags and variables that are set, cleared, incremented, and/or decremented along the way. It can detect the following issues:

* Cycles within your story -- This may not actually be a problem, you might want it this way. But StorySlider will not traverse a cycle within a branch as of right now, because I really, *really* don't want to deal with the halting problem at the moment, especially given that it is a proven NP-hard, non-computable problem, and my solving it would basically destroy decades of known computer science axioms, so there.
* Dead ends -- If any path hits a point where the reader can't proceed due to not meeting any of the conditions for the links exiting a node, it'll tell you.
* Underflows -- If any decrement operation on a numeric variable would cause it to drop below zero, StorySlider'll tell you. (This may not be an issue for your platform, but some platforms do not allow for negative values.)
* "Fact" flags that are reset -- Flags that start with `first_` are treated as ones that should only be set a single time within a path, and never reset or cleared. This is particularly useful if you want to make sure a character doesn't "meet" a person more than once along the same path, for example. If any flag starting with `first_` is seen to be set more than once, StorySlider'll tell you.
* Missing nodes -- Any links that go to non-existent nodes will be noted.
* Unfinished endings -- Any nodes without exit links, which do not also have the `ending` flag set to true, will be noted. This helps you determine unfinished branches.
* Unfollowable links -- If any link's conditions will *never* be met (e.g. if the link requires a flag to be true, but the flag will always be false at that node), StorySlider will tell you.

Future plans are to let StorySlider automatically generate a Dot graph from your YAML file, and maybe even generate the story code itself, although that second one is questionable...

More later!
