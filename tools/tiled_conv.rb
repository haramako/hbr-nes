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
    @vars = []
    @world_width = w / AREA_WIDTH
    @world_height = h / AREA_HEIGHT

    if @gd2_loaded
      @text_conv = NesTools::TextConverter.new('res/images/misaki_gothic.png')
    else
      @text_conv = NesTools::TextConverter.new()
    end
    @text_conv.conv("VERSION.") # 文字を追加

    conv_text
    
    make_font
    make_sprite_image
    make_title_image
    make_enemy_image

    make_face_image
    
    conv_sound
    
    conv_misc_text

    IO.binwrite "res/fs_data.bin", @fs.bin
    IO.write 'src/resource.fc', ERB.new(DATA.read,trim_mode: '-').result(binding)
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

  def get_tile_pal(tset, width, x, y)
    p0 = tset.tiles[y*width+x]&.palette || 0
    p1 = tset.tiles[y*width+x+1]&.palette || 0
    p2 = tset.tiles[(y+1)*width+x]&.palette || 0
    p3 = tset.tiles[(y+1)*width+x+1]&.palette || 0
    [p0,p1,p2,p3].max
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

  def make_enemy_image
    return unless @gd2_loaded
    img = GD2::Image.import( 'res/images/enemy01.png' )
    tset = NesTools::TileSet.new
    tset.add_from_img( img )
    IO.binwrite 'res/images/enemy01.chr', tset.bin
    
    nes_pal = NesTools::Palette.nespal(img)[0...8]

    tile_pal = []
    2.times do |y|
      3.times do |x|
        tile_pal << ( (get_tile_pal(tset, 12, x*2  , y*2  ) << 0) | 
                      (get_tile_pal(tset, 12, x*2+2, y*2  ) << 2) |
                      (get_tile_pal(tset, 12, x*2  , y*2+2) << 4) |
                      (get_tile_pal(tset, 12, x*2+2, y*2+2) << 6) )
      end
    end
    
    IO.binwrite 'res/images/enemy01.nespal', nes_pal.pack('c*')
    IO.binwrite 'res/images/enemy01.tilepal', tile_pal.pack('c*')
    @fs.add tile_pal, 'ENEMY01_PALLET'
    @vars.push ['ENEMY01_PAL', nes_pal]
    @vars.push ['ENEMY01_ATTR', tile_pal]
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
  
  # faceイメージの作成
  def make_face_image
    if @gd2_loaded
      require 'gd2-ffij'
      img = GD2::Image.import( 'res/images/face.png' )

      tset = NesTools::TileSet.new
      tset.add_from_img( img )
      tset.reflow!

      # パレットセットを作成
      face_pal_set = NesTools::Palette.nespal(img)[0...128]
      
      face_pals = []
      tset.tiles.each_slice(128).each do |tiles|
        face_pals << tiles.each_slice(4).map{|t| t[0].palette % 4}
      end

      JSON.dump( {pal_set: face_pal_set, tile_pals: face_pals}, open('res/images/tmp_face_pal.json','w') ) # 一時的に保存

      IO.binwrite("res/images/face.chr", tset.bin)
    else
      json = JSON.parse( IO.read('res/images/tmp_face_pal.json') ) 
      face_pal_set = json['pal_set']
      face_pals = json['tile_pals']
    end

    @face_pal_set = face_pal_set
    @fs.tag :FACE_PAL_BASE
    face_pals.each do |pals|
      @fs.add pals
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
const FACE_PAL_SET = <%=@face_pal_set%>;

<%- @vars.each do |v| -%>
const <%=v[0]%> = <%=v[1]%>;
<%- end -%>
