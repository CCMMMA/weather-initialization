import argparse
from pyvantagepro import VantagePro2
import time
import csv
from datetime import datetime

def main():
    parser = argparse.ArgumentParser(description="Fetch weather data from Vantage Pro 2.")
    parser.add_argument("url", type=str, help="URL of the Vantage Pro 2 device (e.g., 'tcp:127.0.0.1:22222')")
    parser.add_argument("--start", type=str, default="2009-01-01 01:01",
                        help="Start date for fetching archives in 'YYYY-MM-DD HH:MM' format (default: 2009-01-01 01:01)")
    parser.add_argument("--output", type=str, default="weather_data.csv", help="Output CSV file name (default: weather_data.csv)")
    args = parser.parse_args()

    try:
        start_date = datetime.strptime(args.start, '%Y-%m-%d %H:%M')
    except ValueError:
        print("Error: start_date must be in 'YYYY-MM-DD HH:MM' format.")
        return

    url = args.url
    filename = args.output
    try:
        device = VantagePro2.from_url(url, timeout=3)
    except Exception as e:
        print(f"Error connecting to device: {e}")
        return

    start = time.time()
    try:
        datas = device.get_archives()
    except Exception as e:
        print(f"Error fetching archives: {e}")
        return
    finally:
        device.close()

    print("Data retrieval time:", time.time() - start)

    packet_data = []
    for data in datas:
        if data['Datetime'] >= start_date:
            d = {}
            for key, value in data.items():
                if key == 'Datetime':
                    d[key] = value
                else:
                    d[key] = value
            packet_data.append(d)

    if not packet_data:
        print("No archive data found for the requested date range.")
        return

    try:
        with open(filename, mode='w', newline='') as file:
            fieldnames = packet_data[0].keys()
            writer = csv.DictWriter(file, fieldnames=fieldnames)
            writer.writeheader()

            for row in packet_data:
                row['Datetime'] = row['Datetime'].strftime('%Y-%m-%d %H:%M:%S')
                writer.writerow(row)

        print(f"Data saved to {filename}")
    except Exception as e:
        print(f"Error writing to file: {e}")

if __name__ == "__main__":
    main()
