// SPDX-License-Identifier: MIT

typedef struct {
    double latitude;
    double longitude;
} CLLocationCoordinate2D;

CLLocationCoordinate2D CLLocationCoordinate2DMake(double latitude, double longitude) {
    return (CLLocationCoordinate2D){ latitude, longitude };
}
