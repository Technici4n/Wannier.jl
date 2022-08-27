# Real space WFs

This page lists functions for processing WFs in real space.

Normally operators are computed in reciprocal space, but sometimes it might be useful to
evaluate them in real space. For example, computing higher moment of WFs.

```@meta
CurrentModule = Wannier
```

## Contents

```@contents
Pages = ["realspace.md"]
Depth = 2
```

## Index

```@index
Pages = ["realspace.md"]
```

## Read/Write real space WFs

```@docs
RGrid
origin
span_vectors
read_realspace_wf
write_realspace_wf
```

## Evaluate operators in real space

```@docs
moment
center
omega
position_op
```