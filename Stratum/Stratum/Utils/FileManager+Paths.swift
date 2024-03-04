//
//  FileManager+Paths.swift
//  Stratum
//
//  Created by Sergiu Corbu on 12.01.2024.
//

import Foundation

extension FileManager {
    
    var rootImagesDirectoryPath: URL {
        let paths = urls(for: .documentDirectory, in: .userDomainMask)
        let imagesFilePath = paths[0].appendingPathComponent("rawImagesDirectory")
        return imagesFilePath
    }
}
