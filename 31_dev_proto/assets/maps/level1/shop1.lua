return {
  version = "1.10",
  luaversion = "5.1",
  tiledversion = "2025.11.21",
  class = "",
  orientation = "orthogonal",
  renderorder = "right-down",
  width = 13,
  height = 14,
  tilewidth = 32,
  tileheight = 32,
  nextlayerid = 10,
  nextobjectid = 53,
  properties = {
    ["game_mode"] = "topdown",
    ["name"] = "home1",
    ["persist_state"] = true
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
      height = 14,
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
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        43, 44, 45, 45, 45, 45, 45, 45, 45, 45, 45, 46, 47,
        59, 61, 126, 126, 126, 126, 126, 126, 126, 126, 126, 62, 63,
        59, 61, 126, 126, 126, 126, 126, 126, 126, 126, 126, 61, 63,
        59, 61, 126, 126, 126, 126, 126, 126, 126, 126, 126, 61, 63,
        59, 61, 126, 126, 126, 126, 126, 126, 126, 126, 126, 61, 63,
        59, 61, 126, 126, 126, 126, 126, 126, 126, 126, 126, 61, 63,
        59, 61, 126, 126, 126, 126, 126, 126, 126, 126, 126, 61, 63,
        59, 61, 126, 126, 126, 126, 125, 125, 125, 126, 126, 61, 63,
        75, 76, 77, 77, 77, 125, 125, 125, 125, 125, 77, 78, 79,
        91, 92, 93, 93, 93, 93, 125, 125, 125, 93, 93, 94, 95,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
      }
    },
    {
      type = "tilelayer",
      x = 0,
      y = 0,
      width = 13,
      height = 14,
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
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 66, 67, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 82, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
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
          y = 64,
          width = 32,
          height = 320,
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
          y = 352,
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
          y = 352,
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
          y = 64,
          width = 32,
          height = 320,
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
          y = 64,
          width = 416,
          height = 32,
          rotation = 0,
          visible = true,
          properties = {}
        },
        {
          id = 11,
          name = "",
          type = "",
          shape = "rectangle",
          x = 32,
          y = 224,
          width = 64,
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
      visible = true,
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
          y = 384,
          width = 96,
          height = 32,
          rotation = 180,
          visible = true,
          properties = {
            ["spawn_x"] = 280,
            ["spawn_y"] = 720,
            ["target_map"] = "assets/maps/level1/area1.lua",
            ["type"] = "portal"
          }
        }
      }
    },
    {
      type = "objectgroup",
      draworder = "topdown",
      id = 5,
      name = "Props",
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
          id = 40,
          name = "",
          type = "",
          shape = "rectangle",
          x = 256,
          y = 128,
          width = 32,
          height = 32,
          rotation = 0,
          gid = 101,
          visible = true,
          properties = {
            ["group"] = "flower1"
          }
        },
        {
          id = 41,
          name = "",
          type = "",
          shape = "rectangle",
          x = 256,
          y = 96,
          width = 32,
          height = 32,
          rotation = 0,
          gid = 85,
          visible = true,
          properties = {
            ["group"] = "flower1"
          }
        },
        {
          id = 42,
          name = "",
          type = "",
          shape = "rectangle",
          x = 288,
          y = 128,
          width = 32,
          height = 32,
          rotation = 0,
          gid = 134,
          visible = true,
          properties = {
            ["group"] = "flower2"
          }
        },
        {
          id = 43,
          name = "",
          type = "",
          shape = "rectangle",
          x = 288,
          y = 96,
          width = 32,
          height = 32,
          rotation = 0,
          gid = 118,
          visible = true,
          properties = {
            ["group"] = "flower2"
          }
        },
        {
          id = 44,
          name = "",
          type = "",
          shape = "rectangle",
          x = 320,
          y = 128,
          width = 32,
          height = 32,
          rotation = 0,
          gid = 100,
          visible = true,
          properties = {
            ["group"] = "flower3"
          }
        },
        {
          id = 45,
          name = "",
          type = "",
          shape = "rectangle",
          x = 320,
          y = 96,
          width = 32,
          height = 32,
          rotation = 0,
          gid = 84,
          visible = true,
          properties = {
            ["group"] = "flower3"
          }
        },
        {
          id = 46,
          name = "",
          type = "",
          shape = "rectangle",
          x = 320,
          y = 64,
          width = 32,
          height = 32,
          rotation = 0,
          gid = 68,
          visible = true,
          properties = {
            ["group"] = "flower3"
          }
        },
        {
          id = 47,
          name = "",
          type = "",
          shape = "rectangle",
          x = 256,
          y = 96,
          width = 32,
          height = 27.75,
          rotation = 0,
          visible = true,
          properties = {
            ["breakable"] = true,
            ["group"] = "flower1",
            ["hp"] = 30,
            ["movable"] = true,
            ["respawn"] = true,
            ["type"] = "collider"
          }
        },
        {
          id = 49,
          name = "",
          type = "",
          shape = "rectangle",
          x = 288,
          y = 96,
          width = 32,
          height = 27.75,
          rotation = 0,
          visible = true,
          properties = {
            ["breakable"] = true,
            ["group"] = "flower2",
            ["hp"] = 30,
            ["movable"] = true,
            ["respawn"] = true,
            ["type"] = "collider"
          }
        },
        {
          id = 50,
          name = "",
          type = "",
          shape = "rectangle",
          x = 320,
          y = 96,
          width = 32,
          height = 27.75,
          rotation = 0,
          visible = true,
          properties = {
            ["breakable"] = true,
            ["group"] = "flower3",
            ["hp"] = 30,
            ["movable"] = true,
            ["respawn"] = true,
            ["type"] = "collider"
          }
        }
      }
    },
    {
      type = "objectgroup",
      draworder = "topdown",
      id = 9,
      name = "NPCs",
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
          id = 52,
          name = "",
          type = "",
          shape = "rectangle",
          x = 64,
          y = 160,
          width = 32,
          height = 32,
          rotation = 0,
          visible = true,
          properties = {
            ["id"] = "merchant_01",
            ["type"] = "merchant"
          }
        }
      }
    }
  }
}
