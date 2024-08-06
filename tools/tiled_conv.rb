#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

$LOAD_PATH << 'nes_tools/lib'

require 'pp'
require 'json'
require 'erb'
require 'nes_tools'


# 8KBごとのバンクに分けられたバッファ
class BankedBuffer
  BANK_SIZE = 0x2000

  attr_reader :buf, :sizes, :addrs, :datas

  def initialize
    @buf = []
    @sizes = []
    @addrs = []
    @datas = []
  end

  def add( data )
    data = data.flatten

    # バンクをまたぐなら
    if ((@buf.size+data.size) / BANK_SIZE) != (@buf.size / BANK_SIZE)
      @buf.concat Array.new(BANK_SIZE - @buf.size % BANK_SIZE){0}
    end

    @datas << data
    @addrs << @buf.size
    @sizes << data.size
    @buf.concat data
  end

  def cur
    @addrs.size
  end

  def bin
    head = @addrs.pack('v*') + @sizes.pack('v*')
    head = head + "\0" * (BANK_SIZE-head.size)
    head + @buf.pack('c*')
  end

  def bank_size
    (@buf.size.to_f / BANK_SIZE).ceil
  end

end

# タイルデータのコンバート
class TiledConverter

  AREA_WIDTH = 16
  AREA_HEIGHT = 15

  ENEMY_TYPE = {
    slime:        {id: 1, slot:[1,0]},
    wow:          {id: 2, slot:[0,0]},
    elevator:     {id: 3, slot:[0,1]},
    block:        {id: 6, slot:[0,0]},
    frog:         {id: 7, slot:[0,1]},
    cookie:       {id: 8, slot:[0,0]},
    chest:        {id: 9, slot:[0,0]},
    lamp:         {id:10, slot:[0,1]},
    gas:          {id:11, slot:[1,0]},
    ghost:        {id:12, slot:[1,0]},
    switch:       {id:13, slot:[0,0]},
    flaged_door:  {id:14, slot:[0,0]},
    portal:       {id:15, slot:[0,0]},
    checkpoint:   {id:16, slot:[0,0]},
    bird:         {id:17, slot:[1,0]},
    statue:       {id:18, slot:[1,0]},
    statue_fire:  {id:19, slot:[0,0]},
    fish:         {id:20, slot:[1,0]},
    watergate:    {id:21, slot:[1,0]},
    colorswitch:  {id:22, slot:[0,1]},
  }

  ITEM_DATA = 
    [
     ['sandal', 'サンダル', 'すごくやわらかいものなら乗れるかも？'],
     ['lamp', 'ランプ', '燭台に火を灯す'],
     ['grobe', 'グローブ', 'これなら、岩を押してもケガしない'],
     ['boots', 'まきもの', '昔、カエルに乗る忍者がいたそうだ・・・'],
     ['omamori', 'お守り', 'ひとだまに触っても祟られない'],
     ['map', '地図', '迷宮で迷わないためには、地図が必要だ'],
     ['gas_mask', 'ガスマスク', 'ガスにあたっても死なない'],
     ['weight', 'おもり', '水に潜れるようになる'],
     ['craw', 'かぎ爪', 'はしごに飛び乗れる'],
     ['wing', '天使の羽', 'すきなチェックポイントに飛べる'],
     ['eye', 'めだま', 'めだまのかたちをしたおっかないオブジェ'],
     ['key', '水門のカギ', '水門をひらくカギ'],
     ['orb1', '悲しみの宝珠', '悲しみの思いが閉じ込められている'],
     ['orb2', '怒りの宝珠', '怒りの思いが閉じ込められている'],
     ['orb3', 'よろこびの宝珠', '喜びの思いが閉じ込められている'],
     ['orb4', '後悔の宝珠', '後悔の思いが閉じ込められている'],
     ['orb5', '嫉妬の宝珠', 'はげしい嫉妬が閉じ込められている'],
     ['orb6', '忘却の宝珠', 'どのような思いも、やがて忘れさられる・・・'],
    ]

  def initialize( filename )
    data = JSON.parse( File.read(filename) )

    begin
      require 'gd2-ffij'
      @gd2_loaded = true
    rescue LoadError
      STDERR.puts "WARING: #{$!}"
      STDERR.puts "please install 'gd2-ffij' gem to convert images."
    end
    
    w = data['width'].to_i
    h = data['height'].to_i
    raise if w % AREA_WIDTH != 0 or h % AREA_HEIGHT != 0
    @fs = NesTools::Fs.new
    @world_width = w / AREA_WIDTH
    @world_height = h / AREA_HEIGHT

    if @gd2_loaded
      @text_conv = NesTools::TextConverter.new('res/images/misaki_gothic.png')
    else
      @text_conv = NesTools::TextConverter.new()
    end
    @text_conv.conv("VERSION.") # 文字を追加

    conv_text
    conv_tile( data )
    conv_item( data )
    conv_item_data
    
    make_font
    make_bg_image
    make_sprite_image
    make_item_image
    make_title_image
    
    conv_sound
    
    conv_misc_text

    IO.binwrite "res/fs_data.bin", @fs.bin
    IO.write 'src/resource.fc', ERB.new(DATA.read,nil,'-').result(binding)
    IO.write 'src/fs_config.fc', @fs.config

  end

  # フォント画像の作成
  def make_font
    return unless @gd2_loaded
    @text_conv.make_image('res/images/text.png')
    IO.write('text.txt', @text_conv.using.join)
    tile_set = NesTools::TileSet.new
    tile_set.add_from_img( GD2::Image.import('res/images/text.png'), pal: :monochrome )
    tile_set.save 'res/images/text.chr'
  end

  def make_sprite_image
    return unless @gd2_loaded
    img = GD2::Image.import( 'res/images/sprite.png' )
    tset = NesTools::TileSet.new
    tset.add_from_img( img )
    tset.reflow!
    IO.binwrite 'res/images/sprite.chr', tset.bin
    nes_pal = NesTools::Palette.nespal(img)[0...128]
    IO.binwrite 'res/images/sprite.nespal', nes_pal.pack('c*')
  end

  def make_item_image
    return unless @gd2_loaded
    img = GD2::Image.import( 'res/images/item.png' )
    tset = NesTools::TileSet.new
    tset.add_from_img( img )
    tset.reflow!
    nes_pal = NesTools::Palette.nespal(img)[0...16]
    tile_pal = tset.tiles.each_slice(4).map{|t| t[0].palette}[0...32]
    IO.binwrite 'res/images/item.chr', tset.bin
    IO.binwrite 'res/images/item.nespal', nes_pal.pack('c*')
    IO.binwrite 'res/images/item.tilepal', tile_pal.pack('c*')
  end

  def make_title_image
    return unless @gd2_loaded
    img = GD2::Image.import( 'res/images/title.png' )
    tset = NesTools::TileSet.new
    tset.add_from_img( img )
    IO.binwrite 'res/images/title.chr', tset.bin
    nes_pal = NesTools::Palette.nespal(img)[0...16]
    pal = tset.tiles.map(&:palette)
    tile_pal = []
    4.times do |y|
      8.times do |x|
        tile_pal << ( (pal[(y*4+0)*32+(x*4+0)] << 0) +
                      (pal[(y*4+0)*32+(x*4+2)] << 2) +
                      (pal[(y*4+2)*32+(x*4+0)] << 4) +
                      (pal[(y*4+2)*32+(x*4+2)] << 6) )
      end
    end
    # p pal.each_slice(32).to_a
    # pp tile_pal.each_slice(8).to_a
    IO.binwrite 'res/images/title.nespal', nes_pal.pack('c*')
    IO.binwrite 'res/images/title.tilepal', tile_pal.pack('c*')
    @fs.add tile_pal, 'TITLE_PALLET'
  end
  
  # BGイメージの作成
  def make_bg_image
    if @gd2_loaded
      require 'gd2-ffij'
      img = GD2::Image.import( 'res/images/character.png' )

      tset = NesTools::TileSet.new
      tset.add_from_img( img )
      tset.reflow!

      # パレットセットを作成
      pal_set = NesTools::Palette.nespal(img)[0...128]
      
      tile_pals = []
      tset.tiles.each_slice(128).each do |tiles|
        tile_pals << tiles.each_slice(4).map{|t| t[0].palette % 4}
      end

      JSON.dump( {pal_set:pal_set, tile_pals: tile_pals}, open('res/images/tmp_pal.json','w') ) # 一時的に保存

      common_tiles = tset.tiles.slice!(0,128) # 共通パーツ相当の128タイルを削除する
      # 一部のタイルを置き換える
      [
       [95,63,1], # 空
       [175,174,1], # 空の黒いバツブロック
      ].each do |to,from,num|
        to -= 32
        from -= 32
        num.times do |n|
          4.times do |i|
            tset.tiles[(to+n)*4+i] = tset.tiles[(from+n)*4+i]
          end
        end
      end
      IO.binwrite("res/images/bg.chr", tset.bin)

      # 共通パーツの作成
      common = NesTools::TileSet.new
      4.times{ common.tiles.concat common_tiles }
      anim = NesTools::TileSet.new
      anim.add_from_img( GD2::Image.import('res/images/anim.png') )
      anim.reflow!
      [
       [0, 4], # 矢印
       [0, 5],
       [0, 6],
       [0, 7],
       [0,31], # 見えない壁
       [0,30], # バッテン
       [1,24], # 水面
       [0,25], # 水中
       [2,26], # 水(左落ち)
       [3,27], # 水(右落ち)
       [4,28], # 水(垂直)
       [6,16], # 歯車
      ].each do |src,dest|
        src *= 4*4
        dest *= 4
        4.times do |i| 
          common.tiles[dest+i*128...dest+i*128+4] = anim.tiles[src+i*4...src+i*4+4]
        end
      end
      IO.binwrite("res/images/bg_common.chr", common.bin)

    else
      json = JSON.parse( IO.read('res/images/tmp_pal.json') ) 
      pal_set = json['pal_set']
      tile_pals = json['tile_pals']
    end

    @pal_set = pal_set
    @fs.tag :TILE_PAL_BASE
    tile_pals.each do |pals|
      @fs.add pals
    end

  end

  # タイルデータの収集
  def conv_tile( data )
    a = Array.new(@world_width*@world_height*AREA_WIDTH*AREA_HEIGHT)

    # レイヤーを重ねる
    layers = data['layers'].select{|x| x['type'] == 'tilelayer'}.reverse
    a.size.times do |i|
      l = layers.find{|layer| layer['data'][i] != 0 }
      raise "Invalid map data" unless l
      a[i] = l['data'][i] - 1
    end

    @fs.tag :TILE_BASE
    @area_types = []
    @world_height.times do |ay|
      @world_width .times do |ax|
        area_type = 0
        d = []
        15.times do |cy|
          16.times do |cx|
            cell = a[(ay*15+cy)*AREA_WIDTH*@world_width + (ax*16+cx)]
            if cell > 32
              area_type = cell / 32 if area_type == 0 and cell % 32 != 31 # 31=空は特別
              cell = cell % 32 + 32
            end
            d[cy*16+cx] = cell
          end
        end
        @fs.add NesTools::Compress::Lzw.compress( d )
        #if ay == 0 and ax == 13
          packed = NesTools::Compress::Lzw.compress( d )
          #IO.binwrite('uc.bin', d.pack('c*'))
          #IO.binwrite('c.bin', packed.pack('c*'))
          raise if NesTools::Compress::Lzw.decompress(packed) != d
        #end
        @area_types << area_type
      end
    end
  end

  # ピクセル数を[エリア番号, エリア内のセルX, エリア内のセルY]に変換する
  def px2area( x, y )
    x = x.to_i/16
    y = (y.to_i/16)-1
    area = (y/AREA_HEIGHT)*@world_width + x/AREA_WIDTH
    [area, x%AREA_WIDTH, y%AREA_HEIGHT]
  end

  # アイテムデータの収集
  def conv_item( data )
    objs = data['layers'].find{|x| x['name'] == 'objects'}
    checkpoints = []
    enemy = Array.new(@world_width*@world_height){[]}
    objs['objects'].each do |obj|
      if obj['properties']
        prop = Hash[obj['properties'].map{|e| [e['name'], e['value']] }]
      else
        prop = {}
      end
      case obj['type']
      when 'checkpoint'
        area, x, y = px2area( obj['x'], obj['y'] )
        checkpoints[prop['id'].to_i] = {name:obj['name'], area:area, x:x*16, y:y*16}
        enemy[area] << {type:'checkpoint', x:x, y:y, p1:prop['id'].to_i, p2:0, p3:0 }
      when 'enemy'
        area, x, y = px2area( obj['x'], obj['y'] )
        type = obj['name'].empty? ? prop['type'] : obj['name']
        enemy[area] << {type:type, x:x, y:y, p1:prop['p1'].to_i, p2:prop['p2'].to_i, p3:prop['p3'].to_i }
      when 'item'
        area, x, y = px2area( obj['x'], obj['y'] )
        id = ITEM_DATA.find_index{|i| i[0] == obj['name'].downcase}
        raise unless id
        enemy[area] << {type:'chest', x:x, y:y, p1:id, p2:0, p3:0 }
      end
    end

    @cp_buf = BankedBuffer.new
    checkpoints.each.with_index do |cp,i|
      name = @text_conv.conv( cp[:name] )
      @cp_buf.add [ cp[:area], cp[:x], cp[:y], name, 0].flatten
    end

    @fs.tag :ENEMY_BASE
    enemy.each.with_index do |area,i|
      area_slot = [0,0]
      area = area.map do |en| 
        if /^portal:(.+)/ === en[:type].downcase
          # ポータルの場合
          type_data =  ENEMY_TYPE[$1.downcase.to_sym]
          type = (128 | type_data[:id])
        else
          # それ以外
          type_data = ENEMY_TYPE[en[:type].downcase.to_sym]
          type = type_data[:id]
        end
        type_data[:slot].each.with_index do |slot,j|
          next if slot == 0
          if area_slot[j] != 0 and area_slot[j] != type_data[:id]
            raise "slot conflict in area (#{i%@world_width},#{i/@world_width}) with #{en[:type]}"
          end
          area_slot[j] = type_data[:id]
        end
        [type, en[:x], en[:y], en[:p1] % 256, en[:p2] % 256, en[:p3] % 256]
      end
      @fs.add [area_slot, area.size, area]
    end
  end

  def conv_item_data

    @item_ids = []
    ITEM_DATA.each do |item|
      @item_ids << item[0].upcase
    end

    @fs.tag :ITEM_NAME_BASE
    ITEM_DATA.each do |item|
      @fs.add @text_conv.conv(item[1])
    end

    @fs.tag :ITEM_DESC_BASE
    ITEM_DATA.each do |item|
      @fs.add @text_conv.conv(item[2])
    end

  end

  def conv_text
    Dir.glob('src/*.fc') do |f|
      d = []
      txt = File.open(f,'rb:UTF-8'){|f| f.read }
      txt.gsub(/_T\(\"(.*?)\"\)/){ d << $1 }
      @text_conv.conv(d.join(''))
    end
  end

  def conv_sound
    @fs.tag :SOUND_BASE
    ['castle1'].each do |f|
      bin = IO.binread( 'res/sound/'+f+'.bin' ).unpack('c*')
      @fs.add bin
    end
  end

  def conv_misc_text
    if @gd2_loaded
      conv = NesTools::TextConverter.new('res/images/misaki_gothic.png')
    else
      conv = NesTools::TextConverter.new()
    end
    
    Dir.glob('res/text/*.txt') do |f|
      text = File.open(f,'rb:UTF-8'){|f| f.read }
      @fs.add [conv.conv(text),0], 'TEXT_'+File.basename(f,'.txt').upcase
    end

    Dir.glob('res/text/*.json') do |f|
      json = JSON.parse( File.open(f,'rb:UTF-8'){|f| f.read } )
      @fs.tag 'TEXT_'+File.basename(f,'.json').upcase
      json.each do |txt|
        @fs.add [conv.conv(txt),0]
      end
    end

    if @gd2_loaded
      conv.make_image( 'res/text/misc_text.png' )
      tile_set = NesTools::TileSet.new
      tile_set.add_from_img( GD2::Image.import('res/text/misc_text.png'), pal: :monochrome )
      tile_set.save 'res/text/misc_text.chr'
    end
  end
  
end

if ARGV.empty?
  puts "Convert Tiled json file to game data."
  puts "usage: ./tile-conv <mapfile.json>"
  exit
end

TiledConverter.new( ARGV[0] )

__END__
const MAP_WIDTH = <%=@world_width%>;
const MAP_HEIGHT = <%=@world_height%>;
const AREA_TYPES = <%=@area_types%>;

const MAP_CHECKPOINT_NUM = <%=@cp_buf.cur%>;
const MAP_CHECKPOINT = <%=@cp_buf.addrs%>;
const MAP_CHECKPOINT_DATA = <%=@cp_buf.buf%>;

<%- @item_ids.each.with_index do |item,i| -%>
const ITEM_ID_<%=item%> = <%= i %>;
<%- end -%>
const PAL_SET = <%=@pal_set%>;
