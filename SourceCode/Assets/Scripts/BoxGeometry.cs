/**********************************************************************************************
* File:         BoxGeometry.cs
* Developer:    Joshua Lanman
* Date:         December 1, 2018
* Description:  This script, when attached to the fogBox prefab, will calculate various
*               geometric properties for the fogBox it is attached to, such as CG, corner
*               locations, mid-face locations, etc.
**********************************************************************************************/

using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;

public class BoxGeometry : MonoBehaviour
{

    /**********************************************************************************************
    *                                   PUBLIC VARIABLES
    **********************************************************************************************/
    [Header("CG Locations")]

    public Vector3 BoxCG;
    public Vector3 Bottom;
    public Vector3 Top;
    public Vector3 Front;
    public Vector3 Back;
    public Vector3 Left;
    public Vector3 Right;

    [Header("Corner Locations")]

    public Vector3 CornerBLF;
    public Vector3 CornerBRF;
    public Vector3 CornerBLB;
    public Vector3 CornerBRB;
    public Vector3 CornerTLF;
    public Vector3 CornerTRF;
    public Vector3 CornerTLB;
    public Vector3 CornerTRB;

    [Header("Normals (Through Thickness)")]

    public Vector3 BottomFace;
    public Vector3 TopFace;
    public Vector3 FrontFace;
    public Vector3 BackFace;
    public Vector3 LeftFace;
    public Vector3 RightFace;

    // Use this for initialization
    void Start()
    {

    }

    // Update is called once per frame
    void Update()
    {
        // Calculate the CG's
        BoxCG = transform.position;

        // Loop through all the children and assign their positions to the proper Vector3
        Transform[] myChildren = GetComponentsInChildren<Transform>();
        foreach (Transform t in myChildren)
        {
            switch (t.name)
            {
                case "Bottom":
                    Bottom = t.position;
                    break;
                case "Top":
                    Top = t.position;
                    break;
                case "Left":
                    Left = t.position;
                    break;
                case "Right":
                    Right = t.position;
                    break;
                case "Front":
                    Front = t.position;
                    break;
                case "Back":
                    Back = t.position;
                    break;
                case "BLF":
                    CornerBLF = t.position;
                    break;
                case "BRF":
                    CornerBRF = t.position;
                    break;
                case "BLB":
                    CornerBLB = t.position;
                    break;
                case "BRB":
                    CornerBRB = t.position;
                    break;
                case "TLF":
                    CornerTLF = t.position;
                    break;
                case "TRF":
                    CornerTRF = t.position;
                    break;
                case "TLB":
                    CornerTLB = t.position;
                    break;
                case "TRB":
                    CornerTRB = t.position;
                    break;
                default:
                    break;
            }

        }

        // Calculate the six through-thickness directed vectors (normalized)
        // Bottom Face
        BottomFace = new Vector3(Top.x - Bottom.x, Top.y - Bottom.y, Top.z - Bottom.z);
        BottomFace.Normalize();

        // Top Face
        TopFace = new Vector3(Bottom.x - Top.x, Bottom.y - Top.y, Bottom.z - Top.z);
        TopFace.Normalize();

        // Front Face
        FrontFace = new Vector3(Back.x - Front.x, Back.y - Front.y, Back.z - Front.z);
        FrontFace.Normalize();

        // Back Face
        BackFace = new Vector3(Front.x - Back.x, Front.y - Back.y, Front.z - Back.z);
        BackFace.Normalize();

        // Left Face
        LeftFace = new Vector3(Right.x - Left.x, Right.y - Left.y, Right.z - Left.z);
        LeftFace.Normalize();

        // Right Face
        RightFace = new Vector3(Left.x - Right.x, Left.y - Right.y, Left.z - Right.z);
        RightFace.Normalize();

    }
}