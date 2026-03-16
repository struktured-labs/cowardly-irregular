-- Rogue Main Design v5 - Final version
-- Fixes: hood outline isolation, scarf coverage, cleaner silhouette

local OUTPUT_PATH = "/home/struktured/projects/cowardly-irregular/assets/sprites/jobs/aseprite/Rogue Main design.aseprite"
local OUTPUT_PNG  = "/home/struktured/projects/cowardly-irregular-sprite-gen/tmp/rogue_build/rogue_preview_v5.png"

local spr = Sprite(256, 256, ColorMode.INDEXED)
spr.filename = OUTPUT_PATH
local pal = spr.palettes[1]
pal:resize(36)
pal:setColor(0, Color{r=0,g=0,b=0,a=0})

local pd={
    {0x0D,0x0A,0x08},{0x20,0x1A,0x14},{0x28,0x28,0x38},{0x3C,0x3C,0x50},
    {0x58,0x58,0x6C},{0x18,0x18,0x24},{0x3A,0x1E,0x38},{0x5B,0x31,0x58},
    {0x7A,0x4A,0x73},{0x45,0x34,0x24},{0x65,0x4C,0x3A},{0x88,0x68,0x54},
    {0x60,0x42,0x28},{0x86,0x56,0x38},{0x38,0x28,0x18},{0x52,0x3C,0x28},
    {0x6A,0x52,0x3C},{0x70,0x4C,0x34},{0xC4,0x96,0x78},{0xF9,0xCA,0xAA},
    {0xE0,0xE0,0xFF},{0x90,0xB0,0xFF},{0x50,0x40,0x30},{0x70,0x5C,0x46},
    {0x90,0x7A,0x60},{0x48,0x44,0x38},{0x78,0x74,0x60},{0xB0,0xAA,0x88},
    {0x40,0x2C,0x18},{0x1A,0x12,0x0C},{0x96,0x68,0x90},
}
for i,rgb in ipairs(pd) do pal:setColor(i,Color{r=rgb[1],g=rgb[2],b=rgb[3],a=255}) end

local OUT=1;local BLCK=2;local HDRK=3;local HMID=4;local HLIT=5
local HSHD=6;local SDRK=7;local SMID=8;local SLIT=9;local LDRK=10
local LMID=11;local LLIT=12;local BBRN=13;local BLIT=14;local BTDK=15
local BTMD=16;local BTLT=17;local SKDK=18;local SKMD=19;local SKLT=20
local EWHT=21;local EIRIS=22;local WRDK=23;local WRMD=24;local WRLT=25
local MEDK=26;local MEMED=27;local MEHG=28;local PCHDK=29;local VDRK=30
local SHGH=31

spr.layers[1].name="Shadow"
local LN={"Cloak_Back","Leg_R","Boot_R","Leg_L","Boot_L","Body","Belt_Pouches",
          "Arm_R","Cloak_Front","Arm_L","Scarf","Head","Hood","Eyes"}
local layers={Shadow=spr.layers[1]}
for _,n in ipairs(LN) do local l=spr:newLayer();l.name=n;layers[n]=l end

local bufs={}
local function buf(n)
    if not bufs[n] then
        bufs[n]=Image(256,256,ColorMode.INDEXED)
        for y=0,255 do for x=0,255 do bufs[n]:putPixel(x,y,0) end end
    end
    return bufs[n]
end
local function p(n,x,y,c) if x>=0 and x<=255 and y>=0 and y<=255 then buf(n):putPixel(x,y,c) end end
local function hline(n,x1,x2,y,c) for x=x1,x2 do p(n,x,y,c) end end
local function vline(n,x,y1,y2,c) for y=y1,y2 do p(n,x,y,c) end end
local function rect(n,x1,y1,x2,y2,c) for y=y1,y2 do for x=x1,x2 do p(n,x,y,c) end end end
local function border(n,x1,y1,x2,y2,c)
    hline(n,x1,x2,y1,c);hline(n,x1,x2,y2,c)
    vline(n,x1,y1,y2,c);vline(n,x2,y1,y2,c)
end
local function dline(n,x1,y1,x2,y2,c)
    local dx,dy=math.abs(x2-x1),math.abs(y2-y1)
    local sx=x1<x2 and 1 or -1;local sy=y1<y2 and 1 or -1;local err=dx-dy
    while true do
        p(n,x1,y1,c); if x1==x2 and y1==y2 then break end
        local e2=2*err
        if e2>-dy then err=err-dy;x1=x1+sx end
        if e2<dx  then err=err+dx;y1=y1+sy end
    end
end

-- Anchors
local CX=125;local FY=215
local FOOT_Y=FY;local ANKLE_Y=FY-10;local KNEE_Y=FY-52
local HIP_Y=FY-78;local WAIST_Y=FY-90;local CHEST_Y=FY-112
local SHLDR_Y=FY-124;local NECK_Y=FY-134;local CHIN_Y=FY-143
local EYE_Y=FY-154;local HEAD_TOP=FY-168

-- ========== SHADOW ==========
for dy=0,3 do hline("Shadow",CX-16+dy*4,CX+16-dy*4,FOOT_Y+1+dy,VDRK) end

-- ========== CLOAK BACK ==========
do
    local ct=SHLDR_Y-6;local cb=FY-8
    for y=ct,cb do
        local t=(y-ct)/(cb-ct+0.001)
        local lx=CX-18-math.floor(t*24)
        local rx=CX+22+math.floor(t*4)
        hline("Cloak_Back",lx,rx,y,HMID)
        hline("Cloak_Back",rx-4,rx,y,HDRK)
        hline("Cloak_Back",lx,lx+3,y,HLIT)
        p("Cloak_Back",math.floor(CX-t*6),y,HDRK)
    end
    local rip={7,11,4,9,2,10,5,8,3,9,6,11,4,8,2,10,5,7,1,9,4,8,6}
    local bl=CX-18-24
    for i,d in ipairs(rip) do
        local bx=bl+(i-1)*3
        if bx<=CX+26 then
            vline("Cloak_Back",bx,cb-d,cb,HLIT)
            vline("Cloak_Back",bx+1,cb-d,cb,HMID)
            p("Cloak_Back",bx,cb-d-1,OUT)
        end
    end
    for y=ct,cb do
        local t=(y-ct)/(cb-ct+0.001)
        p("Cloak_Back",CX-19-math.floor(t*24),y,OUT)
        p("Cloak_Back",CX+23+math.floor(t*4),y,OUT)
    end
    hline("Cloak_Back",CX-18,CX+22,ct-1,OUT)
end

-- ========== RIGHT LEG ==========
do
    for y=HIP_Y,KNEE_Y do
        hline("Leg_R",CX+3,CX+9,y,LMID)
        p("Leg_R",CX+9,y,LDRK);p("Leg_R",CX+3,y,LLIT)
    end
    rect("Leg_R",CX+4,KNEE_Y,CX+11,KNEE_Y+7,LDRK)
    hline("Leg_R",CX+5,CX+10,KNEE_Y+2,LMID)
    for y=KNEE_Y+7,ANKLE_Y do
        hline("Leg_R",CX+3,CX+9,y,LMID)
        p("Leg_R",CX+9,y,LDRK);p("Leg_R",CX+3,y,LLIT)
    end
    for wy=KNEE_Y+10,ANKLE_Y-4,5 do hline("Leg_R",CX+3,CX+9,wy,WRDK) end
    vline("Leg_R",CX+2,HIP_Y,ANKLE_Y,OUT);vline("Leg_R",CX+10,HIP_Y,ANKLE_Y,OUT)
end

-- ========== RIGHT BOOT ==========
do
    local bx=CX+2;local by=ANKLE_Y
    rect("Boot_R",bx,by,bx+8,by+9,BTMD)
    rect("Boot_R",bx-1,by+9,bx+10,by+13,BTDK)
    p("Boot_R",bx+11,by+10,BTDK);p("Boot_R",bx+11,by+11,BTDK)
    vline("Boot_R",bx+1,by+1,by+8,BTLT)
    hline("Boot_R",bx,bx+8,by+4,WRDK);p("Boot_R",bx+4,by+4,MEMED)
    border("Boot_R",bx-2,by-1,bx+12,by+14,OUT)
end

-- ========== LEFT LEG (bent evasive) ==========
do
    for y=HIP_Y,KNEE_Y-8 do
        local t=(y-HIP_Y)/(KNEE_Y-8-HIP_Y+0.001)
        local ox=math.floor(t*-10)
        hline("Leg_L",CX-8+ox,CX-2+ox,y,LMID)
        p("Leg_L",CX-8+ox,y,LLIT);p("Leg_L",CX-2+ox,y,LDRK)
    end
    local kx=CX-18
    rect("Leg_L",kx-3,KNEE_Y-9,kx+4,KNEE_Y+3,LLIT)
    border("Leg_L",kx-4,KNEE_Y-10,kx+5,KNEE_Y+4,OUT)
    for y=KNEE_Y+3,ANKLE_Y-6 do
        local t=(y-(KNEE_Y+3))/(ANKLE_Y-6-(KNEE_Y+3)+0.001)
        local ox=math.floor(t*6)
        hline("Leg_L",kx-3+ox,kx+3+ox,y,LMID)
        p("Leg_L",kx-3+ox,y,LLIT)
    end
    for wy=KNEE_Y+6,ANKLE_Y-10,5 do
        for wx=kx-5,kx+6 do
            if buf("Leg_L"):getPixel(wx,wy)~=0 then buf("Leg_L"):putPixel(wx,wy,WRDK) end
        end
    end
    border("Leg_L",CX-22,HIP_Y-1,CX-1,ANKLE_Y,OUT)
end

-- ========== LEFT BOOT ==========
do
    local bx=CX-20;local by=ANKLE_Y-4
    rect("Boot_L",bx-1,by,bx+7,by+9,BTMD)
    rect("Boot_L",bx-5,by+9,bx+8,by+13,BTDK)
    p("Boot_L",bx-6,by+10,BTDK);p("Boot_L",bx-6,by+11,BTDK);p("Boot_L",bx-7,by+10,BTDK)
    rect("Boot_L",bx+8,by+9,bx+10,by+13,BTMD)
    vline("Boot_L",bx,by+1,by+8,BTLT)
    hline("Boot_L",bx-1,bx+7,by+4,WRDK);p("Boot_L",bx+3,by+4,MEMED)
    border("Boot_L",bx-8,by-1,bx+11,by+14,OUT)
end

-- ========== BODY ==========
do
    for y=CHEST_Y,WAIST_Y do
        local t=(y-CHEST_Y)/(WAIST_Y-CHEST_Y+0.001)
        local hw=math.floor(11-t*4);local lean=math.floor(t*3)
        hline("Body",CX-hw-lean,CX+hw-lean,y,LMID)
        hline("Body",CX-hw-lean,CX-hw+1-lean,y,LDRK)
        hline("Body",CX+hw-2-lean,CX+hw-lean,y,LLIT)
    end
    dline("Body",CX-5,CHEST_Y+3,CX+8,CHEST_Y+10,LDRK)
    rect("Body",CX-14,SHLDR_Y,CX-8,SHLDR_Y+6,LDRK)
    hline("Body",CX-13,CX-9,SHLDR_Y+1,LMID)
    border("Body",CX-15,SHLDR_Y-1,CX-7,SHLDR_Y+7,OUT)
    rect("Body",CX+5,SHLDR_Y,CX+12,SHLDR_Y+6,LMID)
    hline("Body",CX+6,CX+11,SHLDR_Y+1,LLIT)
    border("Body",CX+4,SHLDR_Y-1,CX+13,SHLDR_Y+7,OUT)
    for y=CHEST_Y,WAIST_Y do
        local t=(y-CHEST_Y)/(WAIST_Y-CHEST_Y+0.001)
        local hw=math.floor(11-t*4);local lean=math.floor(t*3)
        p("Body",CX-hw-lean-1,y,OUT);p("Body",CX+hw-lean+1,y,OUT)
    end
    hline("Body",CX-11,CX+11,CHEST_Y-1,OUT)
    hline("Body",CX-14,CX+8,WAIST_Y+1,OUT)
end

-- ========== BELT & POUCHES ==========
do
    local by=WAIST_Y+2
    rect("Belt_Pouches",CX-13,by,CX+9,by+7,BBRN)
    border("Belt_Pouches",CX-14,by-1,CX+10,by+8,OUT)
    hline("Belt_Pouches",CX-12,CX+8,by+2,BLIT)
    rect("Belt_Pouches",CX-2,by+2,CX+3,by+6,MEDK)
    p("Belt_Pouches",CX+1,by+4,MEHG)
    border("Belt_Pouches",CX-3,by+1,CX+4,by+7,OUT)
    rect("Belt_Pouches",CX-16,by+8,CX-9,by+19,BBRN)
    border("Belt_Pouches",CX-17,by+7,CX-8,by+20,OUT)
    hline("Belt_Pouches",CX-15,CX-10,by+10,BLIT)
    rect("Belt_Pouches",CX-15,by+20,CX-9,by+27,PCHDK)
    border("Belt_Pouches",CX-16,by+19,CX-8,by+28,OUT)
    hline("Belt_Pouches",CX-14,CX-10,by+22,BBRN)
    rect("Belt_Pouches",CX+6,by,CX+10,by+7,PCHDK)
    border("Belt_Pouches",CX+5,by-1,CX+11,by+8,OUT)
    p("Belt_Pouches",CX-4,by+9,MEDK);p("Belt_Pouches",CX-3,by+9,MEDK)
    p("Belt_Pouches",CX-4,by+10,OUT);p("Belt_Pouches",CX-3,by+10,OUT)
end

-- ========== BACK ARM ==========
do
    for y=SHLDR_Y+4,SHLDR_Y+24 do
        hline("Arm_R",CX+8,CX+14,y,LMID)
        p("Arm_R",CX+8,y,LLIT);p("Arm_R",CX+14,y,LDRK)
    end
    rect("Arm_R",CX+9,SHLDR_Y+24,CX+15,SHLDR_Y+28,LDRK)
    for y=SHLDR_Y+28,SHLDR_Y+46 do hline("Arm_R",CX+8,CX+14,y,LMID) end
    for wy=SHLDR_Y+30,SHLDR_Y+42,4 do hline("Arm_R",CX+8,CX+14,wy,WRDK) end
    local hx,hy=CX+8,SHLDR_Y+46
    rect("Arm_R",hx,hy,hx+6,hy+5,SKMD);hline("Arm_R",hx,hx+6,hy+1,SKLT)
    for i=0,5 do p("Arm_R",hx+i,hy-1,SKDK) end
    border("Arm_R",hx-1,hy-1,hx+7,hy+6,OUT)
    vline("Arm_R",CX+7,SHLDR_Y+4,SHLDR_Y+46,OUT)
    vline("Arm_R",CX+15,SHLDR_Y+4,SHLDR_Y+46,OUT)
end

-- ========== CLOAK FRONT (good coverage) ==========
do
    local ct=SHLDR_Y-4;local cb=WAIST_Y+30
    for y=ct,cb do
        local t=(y-ct)/(cb-ct+0.001)
        local lx=CX-20-math.floor(t*10)
        local rx=CX+8-math.floor(t*16)
        if rx>lx then
            hline("Cloak_Front",lx,rx,y,HMID)
            hline("Cloak_Front",lx,lx+2,y,HLIT)
            hline("Cloak_Front",rx-3,rx,y,HSHD)
        end
    end
    rect("Cloak_Front",CX-13,SHLDR_Y-3,CX-8,SHLDR_Y+2,MEDK)
    p("Cloak_Front",CX-11,SHLDR_Y-1,MEHG)
    border("Cloak_Front",CX-14,SHLDR_Y-4,CX-7,SHLDR_Y+3,OUT)
    local torn={5,9,3,7,2,8,4,10,1,6,4,8,2,7,3}
    local tbx=CX-30;local tby=cb
    for i,d in ipairs(torn) do
        local fx=tbx+(i-1)*3
        if fx<=CX+8 then
            vline("Cloak_Front",fx,tby-d,tby,HLIT)
            vline("Cloak_Front",fx+1,tby-d,tby,HMID)
            p("Cloak_Front",fx,tby-d-1,OUT)
        end
    end
    for y=ct,cb do
        local t=(y-ct)/(cb-ct+0.001)
        p("Cloak_Front",CX-21-math.floor(t*10),y,OUT)
    end
    hline("Cloak_Front",CX-20,CX+8,ct-1,OUT)
end

-- ========== FRONT ARM (emerges from cloak) ==========
do
    -- Arm emerges horizontally-left from cloak edge at chest level
    -- Only visible portion: forearm emerging + hand
    local fa_start_x=CX-20
    local fa_y=CHEST_Y+6

    -- Forearm (emerges from cloak gap, goes left)
    for i=0,15 do
        local fx=fa_start_x-i
        local fy=fa_y-math.floor(i*0.4)  -- slight upward angle
        p("Arm_L",fx,fy,LLIT)
        p("Arm_L",fx,fy+1,LMID)
        p("Arm_L",fx,fy+2,LMID)
        p("Arm_L",fx,fy+3,LDRK)
    end
    -- Bracer
    local bx=fa_start_x-5;local bby=fa_y-2
    rect("Arm_L",bx-8,bby,bx,bby+5,WRMD)
    hline("Arm_L",bx-7,bx-1,bby+1,WRLT)
    p("Arm_L",bx-6,bby+3,MEDK);p("Arm_L",bx-2,bby+3,MEDK)
    border("Arm_L",bx-9,bby-1,bx+1,bby+6,OUT)
    -- Hand
    local hx=fa_start_x-22;local hy=fa_y-4
    rect("Arm_L",hx,hy,hx+6,hy+5,SKMD)
    hline("Arm_L",hx+1,hx+5,hy+1,SKLT)
    for i=0,5 do p("Arm_L",hx-1+i,hy-1,SKDK) end
    p("Arm_L",hx-1,hy-2,SKMD);p("Arm_L",hx,hy-2,SKDK)
    p("Arm_L",hx+5,hy-1,SKMD);p("Arm_L",hx+6,hy-1,SKDK);p("Arm_L",hx+7,hy,SKDK)
    border("Arm_L",hx-2,hy-3,hx+8,hy+6,OUT)
    -- Cloak fold at emergence point
    p("Cloak_Front",fa_start_x+1,fa_y-3,HLIT)
    p("Cloak_Front",fa_start_x+1,fa_y-2,HLIT)
    p("Cloak_Front",fa_start_x,fa_y-1,HMID)
    p("Cloak_Front",fa_start_x,fa_y+4,HDRK)
end

-- ========== SCARF ==========
-- Key: reduce chest drape height so cloak covers most of it
do
    -- Neck band
    for y=NECK_Y,CHIN_Y-5 do
        hline("Scarf",CX-7,CX+7,y,SMID)
        p("Scarf",CX-6,y,SDRK);p("Scarf",CX+6,y,SDRK)
        p("Scarf",CX-8,y,OUT);p("Scarf",CX+8,y,OUT)
    end
    hline("Scarf",CX-7,CX+7,NECK_Y-1,OUT)
    -- Face wrap (main band)
    for y=CHIN_Y-5,CHIN_Y+3 do
        hline("Scarf",CX-8,CX+8,y,SMID)
        p("Scarf",CX-3,y,SDRK);p("Scarf",CX+2,y,SDRK)
        p("Scarf",CX,y,SLIT)
        p("Scarf",CX-9,y,OUT);p("Scarf",CX+9,y,OUT)
    end
    hline("Scarf",CX-8,CX+8,CHIN_Y-6,OUT)
    hline("Scarf",CX-8,CX+8,CHIN_Y+4,OUT)
    hline("Scarf",CX-6,CX+6,CHIN_Y-4,SLIT)
    -- Short chest drape (only 8 rows - cloak will cover most of it)
    for y=CHIN_Y+3,CHIN_Y+11 do
        local t=(y-(CHIN_Y+3))/8.0
        local hw=math.floor(8+t*2)
        hline("Scarf",CX-hw,CX+hw,y,SMID)
        hline("Scarf",CX-hw,CX-hw+2,y,SDRK)
    end
    hline("Scarf",CX-10,CX+10,CHIN_Y+12,OUT)
    -- Highlight
    hline("Scarf",CX-5,CX+5,NECK_Y+2,SHGH)
    hline("Scarf",CX-4,CX+4,CHIN_Y-2,SHGH)
    -- Small trailing end (short)
    local tx=CX+9
    for i=0,10 do
        hline("Scarf",tx,tx+3,CHIN_Y+3+i,SMID)
    end
    vline("Scarf",tx-1,CHIN_Y+3,CHIN_Y+13,OUT)
    p("Scarf",tx+3,CHIN_Y+10,OUT);p("Scarf",tx+2,CHIN_Y+12,OUT);p("Scarf",tx+1,CHIN_Y+13,OUT)
end

-- ========== HEAD (minimal skin strip) ==========
do
    for y=CHIN_Y-7,CHIN_Y-5 do hline("Head",CX-4,CX+4,y,SKDK) end
    p("Head",CX,EYE_Y+4,BLCK);p("Head",CX-1,EYE_Y+4,SKDK)
    hline("Head",CX-7,CX+7,EYE_Y+2,HSHD)
    hline("Head",CX-7,CX+7,EYE_Y+3,HDRK)
end

-- ========== HOOD (fixed: no stray outline pixels) ==========
do
    -- Main hood shape
    for y=HEAD_TOP,HEAD_TOP+28 do
        local t=(y-HEAD_TOP)/28.0
        local hw
        if t<0.15 then hw=math.floor(1+t*60)
        elseif t<0.55 then hw=math.floor(10+(t-0.15)*15)
        else hw=math.floor(16-(t-0.55)*8) end
        hw=math.max(1,math.min(hw,16))
        local bx=CX-2
        hline("Hood",bx-hw,bx+hw+3,y,HMID)
        if t>0.25 then hline("Hood",bx-hw+3,bx+hw,y,HSHD) end
        p("Hood",bx-hw,y,HLIT);p("Hood",bx+hw+3,y,HLIT)
    end
    -- Hood brim
    for y=HEAD_TOP+20,EYE_Y+4 do
        local t=(y-(HEAD_TOP+20))/(EYE_Y+4-(HEAD_TOP+20)+0.001)
        local li=CX-10-math.floor(t*2);local ri=CX+8+math.floor(t*2)
        hline("Hood",li-6,li-1,y,HMID);hline("Hood",ri+1,ri+5,y,HLIT)
        hline("Hood",li,li+3,y,HSHD);hline("Hood",ri-3,ri,y,HSHD)
        p("Hood",li-7,y,OUT);p("Hood",ri+6,y,OUT)
    end
    -- Fold details
    vline("Hood",CX,HEAD_TOP+2,HEAD_TOP+16,HDRK)
    vline("Hood",CX-5,HEAD_TOP+8,HEAD_TOP+22,HSHD)
    vline("Hood",CX+7,HEAD_TOP+8,HEAD_TOP+22,HSHD)
    -- Rear hood
    rect("Hood",CX-4,EYE_Y+4,CX+14,EYE_Y+12,HMID)
    hline("Hood",CX-4,CX+14,EYE_Y+3,OUT)
    hline("Hood",CX-4,CX+14,EYE_Y+13,OUT)
    -- TOP OUTLINE: Only outline where hood is NOT filled by face shadow
    -- Use a simple connected arc, no isolated pixels
    -- The fill above at HEAD_TOP+20 is the solid dome, we outline only the top portion
    -- Track the outer edge from fill loop above and just outline those same rows
    for y=HEAD_TOP,HEAD_TOP+19 do
        local t=(y-HEAD_TOP)/28.0  -- same formula as fill
        local hw
        if t<0.15 then hw=math.floor(1+t*60)
        elseif t<0.55 then hw=math.floor(10+(t-0.15)*15)
        else hw=math.floor(16-(t-0.55)*8) end
        hw=math.max(1,math.min(hw,16))
        local bx=CX-2
        -- Only outline the pixel OUTSIDE the fill (fill goes from bx-hw to bx+hw+3)
        p("Hood",bx-hw-1,y,OUT)
        p("Hood",bx+hw+4,y,OUT)
    end
    -- Top cap: single clean horizontal line connecting left+right outlines at peak
    -- The hood peak is at HEAD_TOP where hw=1, so range is CX-3 to CX+4
    hline("Hood",CX-3,CX+4,HEAD_TOP-1,OUT)
end

-- ========== EYES ==========
do
    local ey=EYE_Y;local lx=CX-5;local rx=CX+2
    p("Eyes",lx,ey-1,OUT);p("Eyes",lx+1,ey-1,OUT)
    p("Eyes",lx,ey,EWHT);p("Eyes",lx+1,ey,EWHT)
    p("Eyes",lx,ey+1,EIRIS);p("Eyes",lx+1,ey+1,EWHT)
    p("Eyes",rx,ey-1,OUT);p("Eyes",rx+1,ey-1,OUT)
    p("Eyes",rx,ey,EWHT);p("Eyes",rx+1,ey,EWHT)
    p("Eyes",rx,ey+1,EWHT);p("Eyes",rx+1,ey+1,EIRIS)
    hline("Eyes",lx-1,rx+2,ey-2,HDRK);hline("Eyes",lx-1,rx+2,ey+2,HDRK)
    p("Eyes",lx-2,ey,HDRK);p("Eyes",lx-2,ey+1,HDRK)
    p("Eyes",rx+3,ey,HDRK);p("Eyes",rx+3,ey+1,HDRK)
end

-- ========== APPLY CELS ==========
local ALL={"Shadow","Cloak_Back","Leg_R","Boot_R","Leg_L","Boot_L",
           "Body","Belt_Pouches","Arm_R","Cloak_Front","Arm_L",
           "Scarf","Head","Hood","Eyes"}
for _,lname in ipairs(ALL) do
    local layer=layers[lname]
    if layer and bufs[lname] then
        local cel=layer:cel(1)
        if not cel then cel=spr:newCel(layer,spr.frames[1]) end
        cel.image=bufs[lname];cel.position=Point(0,0)
    end
end

spr:saveAs(OUTPUT_PATH)
print("Saved: "..OUTPUT_PATH)
spr:saveCopyAs(OUTPUT_PNG)
print("Preview: "..OUTPUT_PNG)
