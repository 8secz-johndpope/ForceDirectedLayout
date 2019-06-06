# ForceDirectedLayout

Custom subclass of [UICollectionViewLayout](https://developer.apple.com/documentation/uikit/uicollectionviewlayout) that goes for a force directed positionning of the cells:

- Cells are attracted to the center of the view
- Cells are repulsed by each other

You should tweak the `stiffness` and `charge` variables before using it.

More info on how this layout works in the [blog post](https://blog.krugazor.eu/2019/06/06/fdlayout/)
