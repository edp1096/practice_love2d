return {
  version = "1.10",
  luaversion = "5.1",
  tiledversion = "2025.11.21",
  class = "",
  orientation = "orthogonal",
  renderorder = "right-down",
  width = 25,
  height = 24,
  tilewidth = 32,
  tileheight = 32,
  nextlayerid = 13,
  nextobjectid = 56,
  properties = {
    ["ambient"] = "day",
    ["bgm"] = "level1",
    ["game_mode"] = "topdown",
    ["name"] = "level1_area4"
  },
  tilesets = {
    {
      name = "tileset_area4",
      firstgid = 1,
      class = "",
      tilewidth = 32,
      tileheight = 32,
      spacing = 0,
      margin = 0,
      columns = 27,
      image = "tileset_area4.png",
      imagewidth = 864,
      imageheight = 576,
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
        width = 16,
        height = 16
      },
      properties = {},
      wangsets = {},
      tilecount = 486,
      tiles = {}
    },
    {
      name = "poison_jar",
      firstgid = 487,
      class = "",
      tilewidth = 32,
      tileheight = 32,
      spacing = 0,
      margin = 0,
      columns = 9,
      image = "poison_jar.png",
      imagewidth = 288,
      imageheight = 32,
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
      tilecount = 9,
      tiles = {
        {
          id = 0,
          animation = {
            {
              tileid = 0,
              duration = 100
            },
            {
              tileid = 1,
              duration = 100
            },
            {
              tileid = 2,
              duration = 100
            },
            {
              tileid = 3,
              duration = 100
            },
            {
              tileid = 4,
              duration = 100
            },
            {
              tileid = 5,
              duration = 100
            },
            {
              tileid = 6,
              duration = 100
            },
            {
              tileid = 7,
              duration = 100
            },
            {
              tileid = 8,
              duration = 100
            }
          }
        }
      }
    }
  },
  layers = {
    {
      type = "tilelayer",
      x = 0,
      y = 0,
      width = 25,
      height = 24,
      id = 1,
      name = "Ground",
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
        184, 184, 184, 184, 184, 184, 184, 184, 184, 184, 184, 462, 463, 464, 184, 184, 184, 184, 184, 184, 184, 184, 184, 184, 184,
        184, 184, 184, 184, 184, 184, 184, 184, 184, 184, 184, 462, 463, 464, 184, 184, 184, 184, 184, 184, 184, 184, 184, 184, 184,
        184, 184, 184, 184, 184, 184, 184, 184, 184, 184, 181, 462, 463, 464, 181, 181, 181, 181, 181, 181, 181, 181, 181, 181, 181,
        184, 181, 118, 118, 118, 118, 118, 118, 118, 118, 118, 462, 463, 464, 29, 29, 29, 29, 29, 29, 29, 29, 29, 181, 181,
        184, 181, 118, 118, 118, 118, 118, 118, 118, 118, 118, 462, 463, 464, 29, 29, 29, 29, 29, 29, 29, 29, 29, 181, 181,
        184, 181, 118, 118, 118, 118, 118, 118, 118, 118, 118, 462, 463, 464, 29, 29, 29, 29, 29, 29, 29, 29, 29, 181, 181,
        184, 181, 118, 118, 118, 118, 118, 118, 118, 118, 118, 462, 463, 464, 29, 29, 29, 29, 29, 29, 29, 29, 29, 181, 181,
        184, 181, 118, 118, 118, 118, 118, 118, 118, 118, 118, 462, 463, 464, 29, 29, 29, 29, 29, 29, 29, 29, 29, 181, 181,
        184, 181, 118, 118, 118, 118, 118, 118, 118, 118, 118, 462, 463, 464, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29,
        184, 181, 118, 118, 118, 118, 118, 118, 118, 118, 118, 462, 463, 464, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29,
        184, 181, 118, 118, 118, 118, 118, 118, 118, 118, 118, 462, 463, 464, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29,
        184, 181, 118, 118, 118, 118, 118, 118, 118, 118, 118, 462, 463, 464, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29,
        184, 181, 118, 118, 0, 118, 118, 118, 118, 118, 118, 462, 463, 464, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29,
        184, 181, 118, 118, 118, 118, 118, 118, 118, 118, 118, 462, 463, 464, 29, 29, 29, 29, 29, 29, 29, 29, 29, 181, 181,
        184, 181, 118, 118, 118, 118, 118, 118, 118, 118, 118, 462, 463, 464, 29, 29, 29, 29, 29, 29, 29, 29, 29, 181, 181,
        184, 181, 118, 118, 118, 118, 118, 118, 118, 118, 118, 462, 463, 464, 29, 29, 29, 29, 29, 29, 29, 29, 29, 181, 181,
        184, 181, 118, 118, 118, 118, 118, 118, 118, 118, 118, 462, 463, 464, 29, 29, 29, 29, 29, 29, 29, 29, 29, 181, 181,
        184, 181, 181, 181, 181, 181, 181, 181, 181, 181, 118, 435, 436, 437, 29, 181, 181, 181, 181, 181, 181, 181, 181, 181, 181,
        184, 181, 181, 181, 181, 181, 181, 181, 181, 181, 118, 435, 436, 437, 29, 181, 181, 181, 181, 181, 181, 181, 181, 181, 181,
        438, 407, 407, 407, 407, 407, 407, 407, 407, 407, 407, 407, 407, 407, 407, 407, 407, 407, 407, 407, 407, 407, 407, 407, 439,
        462, 434, 434, 434, 434, 434, 434, 434, 434, 434, 434, 434, 434, 434, 434, 434, 434, 434, 434, 434, 434, 434, 434, 434, 464,
        465, 461, 461, 461, 461, 461, 461, 461, 461, 461, 461, 461, 461, 461, 461, 461, 461, 461, 461, 461, 461, 461, 461, 461, 466,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
      }
    },
    {
      type = "tilelayer",
      x = 0,
      y = 0,
      width = 25,
      height = 24,
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
        344, 344, 344, 344, 344, 344, 344, 344, 344, 345, 0, 0, 0, 0, 0, 343, 344, 344, 344, 344, 344, 344, 344, 344, 344,
        344, 344, 344, 344, 344, 344, 344, 344, 344, 345, 0, 0, 0, 0, 0, 343, 344, 344, 344, 344, 344, 344, 344, 344, 344,
        344, 344, 371, 371, 371, 371, 371, 371, 371, 372, 166, 0, 0, 0, 166, 370, 371, 371, 371, 371, 371, 371, 371, 344, 344,
        344, 344, 345, 0, 0, 0, 0, 0, 0, 0, 193, 0, 0, 0, 193, 0, 0, 0, 0, 0, 0, 0, 343, 344, 344,
        344, 344, 345, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 343, 344, 344,
        344, 344, 345, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 343, 344, 344,
        344, 344, 345, 0, 0, 0, 0, 0, 231, 0, 166, 0, 0, 0, 166, 0, 0, 0, 0, 0, 0, 0, 343, 344, 344,
        344, 344, 345, 0, 0, 0, 0, 0, 0, 0, 193, 0, 0, 0, 193, 0, 0, 0, 0, 0, 0, 0, 370, 371, 371,
        344, 344, 345, 355, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 325,
        344, 344, 345, 355, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 352,
        344, 344, 345, 0, 0, 0, 0, 0, 0, 0, 166, 0, 0, 0, 166, 0, 0, 0, 0, 0, 0, 0, 0, 0, 352,
        344, 344, 345, 250, 250, 250, 0, 0, 0, 0, 193, 0, 0, 0, 193, 0, 0, 0, 0, 0, 0, 0, 0, 0, 352,
        344, 344, 345, 250, 487, 250, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 379,
        344, 344, 345, 250, 250, 250, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 316, 344,
        344, 344, 345, 0, 0, 0, 0, 0, 0, 0, 166, 0, 0, 0, 166, 0, 0, 0, 0, 0, 0, 0, 0, 343, 344,
        344, 344, 345, 0, 0, 0, 0, 0, 0, 0, 193, 0, 0, 0, 193, 0, 0, 0, 0, 0, 0, 0, 0, 343, 344,
        344, 344, 317, 317, 317, 317, 317, 317, 317, 317, 318, 0, 0, 0, 316, 317, 317, 317, 317, 317, 317, 317, 317, 317, 344,
        344, 344, 344, 344, 344, 344, 344, 344, 344, 344, 345, 0, 0, 0, 343, 344, 344, 344, 344, 344, 344, 344, 344, 344, 344,
        371, 371, 371, 371, 371, 371, 371, 371, 371, 371, 372, 0, 0, 0, 370, 371, 371, 371, 371, 371, 371, 371, 371, 371, 371,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
      }
    },
    {
      type = "objectgroup",
      draworder = "topdown",
      id = 3,
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
          width = 64,
          height = 768,
          rotation = 0,
          visible = true,
          properties = {}
        },
        {
          id = 3,
          name = "",
          type = "",
          shape = "rectangle",
          x = 736,
          y = 416,
          width = 64,
          height = 352,
          rotation = 0,
          visible = true,
          properties = {}
        },
        {
          id = 37,
          name = "",
          type = "",
          shape = "rectangle",
          x = 448,
          y = 96,
          width = 32,
          height = 32,
          rotation = 0,
          visible = true,
          properties = {}
        },
        {
          id = 38,
          name = "",
          type = "",
          shape = "rectangle",
          x = 0,
          y = 672,
          width = 800,
          height = 96,
          rotation = 0,
          visible = true,
          properties = {}
        },
        {
          id = 40,
          name = "",
          type = "",
          shape = "rectangle",
          x = 320,
          y = 96,
          width = 32,
          height = 32,
          rotation = 0,
          visible = true,
          properties = {}
        },
        {
          id = 41,
          name = "",
          type = "",
          shape = "rectangle",
          x = 448,
          y = 224,
          width = 32,
          height = 32,
          rotation = 0,
          visible = true,
          properties = {}
        },
        {
          id = 42,
          name = "",
          type = "",
          shape = "rectangle",
          x = 320,
          y = 224,
          width = 32,
          height = 32,
          rotation = 0,
          visible = true,
          properties = {}
        },
        {
          id = 43,
          name = "",
          type = "",
          shape = "rectangle",
          x = 448,
          y = 352,
          width = 32,
          height = 32,
          rotation = 0,
          visible = true,
          properties = {}
        },
        {
          id = 44,
          name = "",
          type = "",
          shape = "rectangle",
          x = 320,
          y = 352,
          width = 32,
          height = 32,
          rotation = 0,
          visible = true,
          properties = {}
        },
        {
          id = 45,
          name = "",
          type = "",
          shape = "rectangle",
          x = 448,
          y = 480,
          width = 32,
          height = 32,
          rotation = 0,
          visible = true,
          properties = {}
        },
        {
          id = 46,
          name = "",
          type = "",
          shape = "rectangle",
          x = 320,
          y = 480,
          width = 32,
          height = 32,
          rotation = 0,
          visible = true,
          properties = {}
        },
        {
          id = 47,
          name = "",
          type = "",
          shape = "rectangle",
          x = 0,
          y = 544,
          width = 320,
          height = 64,
          rotation = 0,
          visible = true,
          properties = {}
        },
        {
          id = 48,
          name = "",
          type = "",
          shape = "rectangle",
          x = 480,
          y = 544,
          width = 320,
          height = 64,
          rotation = 0,
          visible = true,
          properties = {}
        },
        {
          id = 50,
          name = "",
          type = "",
          shape = "rectangle",
          x = 0,
          y = 0,
          width = 352,
          height = 96,
          rotation = 0,
          visible = true,
          properties = {}
        },
        {
          id = 51,
          name = "",
          type = "",
          shape = "rectangle",
          x = 448,
          y = 0,
          width = 352,
          height = 96,
          rotation = 0,
          visible = true,
          properties = {}
        },
        {
          id = 52,
          name = "",
          type = "",
          shape = "rectangle",
          x = 736,
          y = 0,
          width = 64,
          height = 256,
          rotation = 0,
          visible = true,
          properties = {}
        },
        {
          id = 53,
          name = "",
          type = "",
          shape = "rectangle",
          x = 96,
          y = 256,
          width = 32,
          height = 64,
          rotation = 0,
          visible = true,
          properties = {}
        }
      }
    },
    {
      type = "objectgroup",
      draworder = "topdown",
      id = 4,
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
          id = 10,
          name = "",
          type = "",
          shape = "rectangle",
          x = 768,
          y = 224,
          width = 32,
          height = 192,
          rotation = 0,
          visible = true,
          properties = {
            ["spawn_x"] = 60,
            ["spawn_y"] = 1100,
            ["target_map"] = "assets/maps/level1/area2.lua",
            ["type"] = "portal"
          }
        },
        {
          id = 49,
          name = "",
          type = "",
          shape = "rectangle",
          x = 320,
          y = 64,
          width = 160,
          height = 32,
          rotation = 0,
          visible = true,
          properties = {
            ["spawn_x"] = 800,
            ["spawn_y"] = 880,
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
      name = "Enemies",
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
          id = 15,
          name = "",
          type = "",
          shape = "rectangle",
          x = 96,
          y = 128,
          width = 32,
          height = 32,
          rotation = 0,
          visible = true,
          properties = {
            ["patrol_points"] = "30,0;-30,0",
            ["type"] = "green_slime"
          }
        },
        {
          id = 16,
          name = "",
          type = "",
          shape = "rectangle",
          x = 96,
          y = 192,
          width = 32,
          height = 32,
          rotation = 0,
          visible = true,
          properties = {
            ["patrol_points"] = "0,30;0,-30",
            ["respawn"] = true,
            ["type"] = "red_slime"
          }
        }
      }
    },
    {
      type = "objectgroup",
      draworder = "topdown",
      id = 6,
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
          id = 20,
          name = "",
          type = "",
          shape = "rectangle",
          x = 608,
          y = 384,
          width = 32,
          height = 32,
          rotation = 0,
          visible = true,
          properties = {
            ["id"] = "townsperson_01",
            ["type"] = "villager_02"
          }
        }
      }
    },
    {
      type = "objectgroup",
      draworder = "topdown",
      id = 7,
      name = "SavePoints",
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
          id = 25,
          name = "",
          type = "",
          shape = "rectangle",
          x = 256,
          y = 192,
          width = 32,
          height = 32,
          rotation = 0,
          visible = true,
          properties = {
            ["id"] = "save4-1",
            ["type"] = "savepoint"
          }
        }
      }
    },
    {
      type = "objectgroup",
      draworder = "topdown",
      id = 12,
      name = "DamageZones",
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
          id = 55,
          name = "",
          type = "",
          shape = "rectangle",
          x = 128,
          y = 384,
          width = 32,
          height = 32,
          rotation = 0,
          visible = true,
          properties = {
            ["cooldown"] = 0.5,
            ["damage"] = 5
          }
        }
      }
    }
  }
}
