import { Component, OnInit } from '@angular/core';
import { Skret} from '../../classes/skret';
import { AppDataService } from '../../services/app-data.service';
import { HttpClientModule } from '@angular/common/http';
import { HttpClient } from '@angular/common/http';

@Component({
  selector: 'app-skret-list',
  templateUrl: './skret-list.component.html',
  styleUrls: ['./skret-list.component.css']
})
export class SkretListComponent implements OnInit{

  constructor(
    private appDataService: AppDataService,
    private http: HttpClient
  ) {}

  skreti!: Skret[];
  closestSkreti!: Skret[];
  filteredSkreti!: Skret[];
  selectedSkret!: Skret;
  currLat = '';
  currLon = '';

  sidebarCollapsed = false;

  toggleSidebar() {
    this.sidebarCollapsed = !this.sidebarCollapsed;
    
  }

  ngOnInit(): void {
    this.getToilets();
    this.getLocation();
  }

  getToilets(): void {
    this.appDataService.getToilets().subscribe((data: any) => {
      this.skreti = data; 
      this.closestSkreti = data;
    });
  }

  getLocation() {
    if (navigator.geolocation) {
      navigator.geolocation.getCurrentPosition(
        (position) => {
          const latitude = position.coords.latitude;
          const longitude = position.coords.longitude;
          this.currLat = latitude.toString();
          this.currLon = longitude.toString();
          this.computeDistances();

          // You can now use latitude and longitude in your application
          // For example, display them on a map or send to a server
        },
        (error) => {
          console.error("Error getting location:", error.message);
        }
      );
    } else {
      console.log("Geolocation is not available.");
    }
  }

  computeDistances(){
    var distances = [];
    for (let s of this.skreti){
      var dist = Math.abs(s.lat - parseFloat(this.currLat)) + Math.abs(s.lon - parseFloat(this.currLon));
      distances.push(dist)
    }

    const indexedFloats = distances.map((value, index) => ({ value, index }));
    indexedFloats.sort((a, b) => a.value - b.value);
    const lowest10Floats = indexedFloats.slice(0, 10);

    const selectedObjects = lowest10Floats.map(item => this.skreti[item.index]);
    this.closestSkreti = selectedObjects;
  }

}
