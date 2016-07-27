/*
Copyright (c) 2014-2016 Timur Gafarov 

Boost Software License - Version 1.0 - August 17th, 2003

Permission is hereby granted, free of charge, to any person or organization
obtaining a copy of the software and accompanying documentation covered by
this license (the "Software") to use, reproduce, display, distribute,
execute, and transmit the Software, and to prepare derivative works of the
Software, and to permit third-parties to whom the Software is furnished to
do so, all subject to the following:

The copyright notices in the Software and this entire statement, including
the above license grant, this restriction and the following disclaimer,
must be included in all copies of the Software, in whole or in part, and
all derivative works of the Software, unless such copies or derivative
works are solely in the form of machine-executable object code generated by
a source language processor.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT
SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.
*/

module dlib.image.hdri;

private
{
    import core.stdc.string;
    import dlib.core.memory;
    import dlib.image.image;
    import dlib.image.color;
}

abstract class SuperHDRImage: SuperImage
{
    override @property PixelFormat pixelFormat()
    {
        return PixelFormat.RGBA_FLOAT;
    }
}

class HDRImage: SuperHDRImage
{
    public:

    override @property uint width()
    {
        return _width;
    }

    override @property uint height()
    {
        return _height;
    }

    override @property uint bitDepth()
    {
        return _bitDepth;
    }

    override @property uint channels()
    {
        return _channels;
    }

    override @property uint pixelSize()
    {
        return _pixelSize;
    }

    override @property ref ubyte[] data()
    {
        return _data;
    }

    override @property SuperImage dup()
    {
        auto res = new HDRImage(_width, _height);
        res.data = _data.dup;
        return res;
    }

    override SuperImage createSameFormat(uint w, uint h)
    {
        return new HDRImage(w, h);
    }

    this(uint w, uint h)
    {
        _width = w;
        _height = h;
        _bitDepth = 32;
        _channels = 4;
        _pixelSize = (_bitDepth / 8) * _channels;
        allocateData();

        pixelCost = 1.0f / (_width * _height);
        progress = 0.0f;
    }

    override Color4f opIndex(int x, int y)
    {
        while(x >= _width) x = _width-1;
        while(y >= _height) y = _height-1;
        while(x < 0) x = 0;
        while(y < 0) y = 0;

        float r, g, b, a;
        auto dataptr = data.ptr + (y * _width + x) * _pixelSize;
        memcpy(&r, dataptr, 4);
        memcpy(&g, dataptr + 4, 4);
        memcpy(&b, dataptr + 4 * 2, 4);
        memcpy(&a, dataptr + 4 * 3, 4);
        return Color4f(r, g, b, a);
    }
    
    override Color4f opIndexAssign(Color4f c, int x, int y)
    {
        while(x >= _width) x = _width-1;
        while(y >= _height) y = _height-1;
        while(x < 0) x = 0;
        while(y < 0) y = 0;

        auto dataptr = data.ptr + (y * _width + x) * _pixelSize;
        memcpy(dataptr, &c.arrayof[0], 4);
        memcpy(dataptr + 4, &c.arrayof[1], 4);
        memcpy(dataptr + 4 * 2, &c.arrayof[2], 4);
        memcpy(dataptr + 4 * 3, &c.arrayof[3], 4);

        return c;
    }

    protected void allocateData()
    {
        _data = new ubyte[_width * _height * _pixelSize];
    }
    
    void free()
    {
        // Do nothing, let GC delete the object
    }

    protected:

    uint _width;
    uint _height;
    uint _bitDepth;
    uint _channels;
    uint _pixelSize;
    ubyte[] _data;
}

SuperImage clamp(SuperImage img, float minv, float maxv)
{
    foreach(x; 0..img.width)
    foreach(y; 0..img.height)
    {
        img[x, y] = img[x, y].clamped(minv, maxv);
    }

    return img;
}

interface SuperHDRImageFactory
{
    SuperHDRImage createImage(uint w, uint h);
}

class HDRImageFactory: SuperHDRImageFactory
{
    SuperHDRImage createImage(uint w, uint h)
    {
        return new HDRImage(w, h);
    }
}

private SuperHDRImageFactory _defaultHDRImageFactory;

SuperHDRImageFactory defaultHDRImageFactory()
{
    if (!_defaultHDRImageFactory)
        _defaultHDRImageFactory = new HDRImageFactory();
    return _defaultHDRImageFactory;
}

class UnmanagedHDRImage: HDRImage
{
    override @property SuperImage dup()
    {
        auto res = New!(UnmanagedHDRImage)(_width, _height);
        res.data[] = data[];
        return res;
    }

    override SuperImage createSameFormat(uint w, uint h)
    {
        return New!(UnmanagedHDRImage)(w, h);
    }

    this(uint w, uint h)
    {
        super(w, h);
    }

    ~this()
    {
        Delete(_data);
    }

    protected override void allocateData()
    {
        _data = New!(ubyte[])(_width * _height * _pixelSize);
    }
    
    override void free()
    {
        Delete(this);
    }
}

class UnmanagedHDRImageFactory: SuperHDRImageFactory
{
    SuperHDRImage createImage(uint w, uint h)
    {
        return New!UnmanagedHDRImage(w, h);
    }
}

SuperImage hdrTonemapGamma(SuperHDRImage img, float gamma) 
{
    return hdrTonemapGamma(img, null, gamma);
}

SuperImage hdrTonemapGamma(SuperHDRImage img, SuperImage output, float gamma)
{
    SuperImage res;
    if (output)
        res = output;
    else
        res = image(img.width, img.height, 3);

    foreach(y; 0..img.height)
    foreach(x; 0..img.width)
    {
        Color4f c = img[x, y];
        float r = c.r ^^ gamma;
        float g = c.g ^^ gamma;
        float b = c.b ^^ gamma;
        res[x, y] = Color4f(r, g, b, c.a);
    }

    return res;
}

