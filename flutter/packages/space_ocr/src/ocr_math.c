#include <stdint.h>
#include <stdlib.h>
#include <math.h>
#ifdef _WIN32
#define EXPORT __declspec(dllexport)
#else
#define EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

EXPORT void ppocr_argmax(const float* data, int64_t rows, int64_t cols,
                         int32_t* indices, float* scores) {
  for (int64_t r=0; r<rows; ++r) {
    const float* line=data+r*cols; int32_t best=0; float score=line[0];
    for(int64_t c=1;c<cols;++c) if(line[c]>score){score=line[c];best=(int32_t)c;}
    indices[r]=best;scores[r]=score;
  }
}

/* DB probability components -> expanded oriented rectangles. All heavy pixel
 * scans stay native; no OpenCV/Python runtime is required in the application. */
EXPORT int32_t ppocr_boxes(const float* map,int32_t height,int32_t width,
                          float threshold,float box_threshold,float unclip,
                          float* boxes,int32_t capacity) {
  const int64_t size=(int64_t)height*width;
  if(size<=0||size>16000000)return -1;
  uint8_t* seen=(uint8_t*)calloc((size_t)size,1);
  int32_t* queue=(int32_t*)malloc((size_t)size*sizeof(int32_t));
  if(!seen||!queue){free(seen);free(queue);return -1;}
  int32_t found=0;
  for(int32_t start=0;start<size;++start){
    if(seen[start]||map[start]<threshold)continue;
    int32_t head=0,tail=1;queue[0]=start;seen[start]=1;
    double sx=0,sy=0,sxx=0,syy=0,sxy=0,prob=0;
    while(head<tail){
      int32_t n=queue[head++],x=n%width,y=n/width;
      sx+=x;sy+=y;sxx+=(double)x*x;syy+=(double)y*y;sxy+=(double)x*y;prob+=map[n];
      for(int dy=-1;dy<=1;++dy)for(int dx=-1;dx<=1;++dx){
        int32_t xx=x+dx,yy=y+dy;if(xx<0||xx>=width||yy<0||yy>=height)continue;
        int32_t k=yy*width+xx;if(!seen[k]&&map[k]>=threshold){seen[k]=1;queue[tail++]=k;}
      }
    }
    if(tail<6||prob/tail<box_threshold)continue;
    double mx=sx/tail,my=sy/tail;
    double angle=.5*atan2(2*(sxy/tail-mx*my),(sxx/tail-mx*mx)-(syy/tail-my*my));
    double c=cos(angle),s=sin(angle),u0=1e30,u1=-1e30,v0=1e30,v1=-1e30;
    for(int32_t i=0;i<tail;++i){double x=queue[i]%width,y=queue[i]/width;
      double u=x*c+y*s,v=-x*s+y*c;if(u<u0)u0=u;if(u>u1)u1=u;if(v<v0)v0=v;if(v>v1)v1=v;
    }
    double w=u1-u0+1,h=v1-v0+1;if(w<3||h<2)continue;
    double d=w*h*unclip/(2*(w+h));u0-=d;u1+=d;v0-=d;v1+=d;
    if(found>=capacity){found=capacity+1;goto done;}
    float* out=boxes+found*9;
    const double u[4]={u0,u1,u1,u0},v[4]={v0,v0,v1,v1};
    for(int i=0;i<4;++i){out[i*2]=(float)(u[i]*c-v[i]*s);out[i*2+1]=(float)(u[i]*s+v[i]*c);}
    out[8]=(float)(prob/tail);found++;
  }
done:
  free(seen);free(queue);return found;
}
