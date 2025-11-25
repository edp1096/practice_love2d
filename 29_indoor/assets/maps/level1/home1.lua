return {
  version = "1.10",
  luaversion = "5.1",
  tiledversion = "2025.11.21",
  class = "",
  orientation = "orthogonal",
  renderorder = "right-down",
  width = 13,
  height = 8,
  tilewidth = 32,
  tileheight = 32,
  nextlayerid = 5,
  nextobjectid = 7,
  properties = {
    ["game_mode"] = "topdown",
    ["name"] = "home1"
  },
  tilesets = {
    {
      name = "tileset_interior1",
      firstgid = 1,
      class = "",
      tilewidth = 32,
      tileheight = 32,
      spacing = 0,
      margin = 0,
      columns = 16,
      image = "tileset_interior1.png",
      imagewidth = 512,
      imageheight = 512,
      transparentcolor = "#ff00ff",
      objectalignment = "unspecified",
      tilerendersize = "tile",
      fillmode = "stretch",
      tileoffset = {
        x = 0,
        y = 0
      },
      grid = {
        orientation = "orthogonal",
        width = 32,
        height = 32
      },
      properties = {},
      wangsets = {},
      tilecount = 256,
      tiles = {}
    }
  },
  layers = {
    {
      type = "tilelayer",
      x = 0,
      y = 0,
      width = 13,
      height = 8,
      id = 1,
      name = "Ground",
      class = "",
      visible = false,
      opacity = 1,
      offsetx = 0,
      offsety = 0,
      parallaxx = 1,
      parallaxy = 1,
      properties = {},
      encoding = "lua",
      data = {
        43, 44, 45, 45, 45, 45, 45, 45, 45, 45, 45, 46, 47,
        59, 61, 126, 126, 126, 126, 126, 126, 126, 126, 126, 62, 63,
        59, 61, 126, 126, 126, 126, 126, 126, 126, 126, 126, 61, 63,
        59, 61, 126, 126, 126, 126, 126, 126, 126, 126, 126, 61, 63,
        59, 61, 126, 126, 126, 126, 126, 126, 126, 126, 126, 61, 63,
        59, 61, 126, 126, 126, 125, 125, 125, 125, 125, 126, 61, 63,
        75, 76, 77, 77, 77, 77, 125, 125, 125, 77, 77, 78, 79,
        91, 92, 93, 93, 93, 93, 93, 93, 93, 93, 93, 94, 95
      }
    },
    {
      type = "tilelayer",
      x = 0,
      y = 0,
      width = 13,
      height = 8,
      id = 2,
      name = "Decos",
      class = "",
      visible = true,
      opacity = 1,
      offsetx = 0,
      offsety = 0,
      parallaxx = 1,
      parallaxy = 1,
      properties = {},
      encoding = "lua",
      data = {
        0, 0, 18, 19, 117, 20, 21, 0, 85, 118, 84, 0, 0,
        0, 0, 34, 35, 0, 36, 37, 0, 101, 134, 100, 0, 0,
        0, 0, 50, 51, 0, 52, 53, 0, 0, 0, 136, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 152, 0, 0,
        0, 0, 66, 67, 116, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 82, 83, 132, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 120, 120, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
      }
    },
    {
      type = "objectgroup",
      draworder = "topdown",
      id = 4,
      name = "Walls",
      class = "",
      visible = true,
      opacity = 1,
      offsetx = 0,
      offsety = 0,
      parallaxx = 1,
      parallaxy = 1,
      properties = {},
      objects = {
        {
          id = 2,
          name = "",
          type = "",
          shape = "rectangle",
          x = 0,
          y = 0,
          width = 32,
          height = 256,
          rotation = 0,
          visible = true,
          properties = {}
        },
        {
          id = 3,
          name = "",
          type = "",
          shape = "rectangle",
          x = 0,
          y = 224,
          width = 192,
          height = 32,
          rotation = 0,
          visible = true,
          properties = {}
        },
        {
          id = 4,
          name = "",
          type = "",
          shape = "rectangle",
          x = 288,
          y = 224,
          width = 128,
          height = 32,
          rotation = 0,
          visible = true,
          properties = {}
        },
        {
          id = 5,
          name = "",
          type = "",
          shape = "rectangle",
          x = 384,
          y = 0,
          width = 32,
          height = 256,
          rotation = 0,
          visible = true,
          properties = {}
        },
        {
          id = 6,
          name = "",
          type = "",
          shape = "rectangle",
          x = 0,
          y = 0,
          width = 416,
          height = 32,
          rotation = 0,
          visible = true,
          properties = {}
        }
      }
    },
    {
      type = "objectgroup",
      draworder = "topdown",
      id = 3,
      name = "Portals",
      class = "",
      visible = false,
      opacity = 1,
      offsetx = 0,
      offsety = 0,
      parallaxx = 1,
      parallaxy = 1,
      properties = {},
      objects = {
        {
          id = 1,
          name = "",
          type = "",
          shape = "rectangle",
          x = 288,
          y = 256,
          width = 96,
          height = 32,
          rotation = 180,
          visible = true,
          properties = {
            ["spawn_x"] = 625,
            ["spawn_y"] = 780,
            ["target_map"] = "assets/maps/level1/area1.lua",
            ["type"] = "portal"
          }
        }
      }
    }
  }
}
