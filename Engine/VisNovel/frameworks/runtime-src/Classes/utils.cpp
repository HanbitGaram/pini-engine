#include "utils.h"

#if PINI_UTILS_WIN32

#else
void Sleep(float t){
	usleep(t * 1000);
}
#endif
